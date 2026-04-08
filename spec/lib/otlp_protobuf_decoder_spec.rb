require "rails_helper"

RSpec.describe OtlpProtobufDecoder do
  # ── Wire-format encoding helpers (used in all tasks) ──────────────────────────

  def pb_varint(int)
    bytes = []
    loop do
      byte = int & 0x7F
      int >>= 7
      byte |= 0x80 if int > 0
      bytes << byte
      break if int.zero?
    end
    bytes.pack("C*")
  end

  # field tag: (field << 3) | wire_type, encoded as varint
  def pb_tag(field, wire) = pb_varint((field << 3) | wire)

  # length-delimited field: tag + varint length + bytes
  def pb_len(field, bytes)
    bytes = bytes.b
    pb_tag(field, 2) + pb_varint(bytes.bytesize) + bytes
  end

  # string field (same as length-delimited but takes a String)
  def pb_str(field, str) = pb_len(field, str.encode("UTF-8").b)

  # varint field
  def pb_int(field, int) = pb_tag(field, 0) + pb_varint(int)

  # fixed64 field — pass Integer (packed as uint64 LE) or Float (IEEE 754 double LE)
  def pb_fixed64(field, value)
    bytes = value.is_a?(Float) ? [value].pack("E") : [value].pack("Q<")
    pb_tag(field, 1) + bytes
  end

  # sfixed64 field (signed 64-bit, wire_type 1)
  def pb_sfixed64(field, value) = pb_tag(field, 1) + [value].pack("q<")

  # packed repeated varints (wire_type 2, contents are concatenated varints)
  def pb_packed_varints(field, ints)
    packed = ints.map { |i| pb_varint(i) }.join.b
    pb_len(field, packed)
  end

  # packed repeated doubles (wire_type 2, contents are 8-byte IEEE 754 doubles)
  def pb_packed_doubles(field, floats)
    packed = floats.map { |f| [f].pack("E") }.join.b
    pb_len(field, packed)
  end

  # ── AnyValue helpers ──────────────────────────────────────────────────────────

  def av_string(str)  = pb_str(1, str)
  def av_bool(val)    = pb_int(2, val ? 1 : 0)
  def av_int(int)     = pb_int(3, int)
  def av_double(flt)  = pb_fixed64(4, flt)

  def kv(key, any_value_bytes)
    pb_str(1, key) + pb_len(2, any_value_bytes)
  end

  # ── Cursor primitives ─────────────────────────────────────────────────────────

  describe OtlpProtobufDecoder::Cursor do
    describe "#read_varint" do
      it "decodes a single-byte value (< 128)" do
        cur = described_class.new([42].pack("C"), 0)
        expect(cur.read_varint).to eq(42)
      end

      it "decodes a multi-byte value (300 = 0xAC 0x02)" do
        cur = described_class.new([0xAC, 0x02].pack("C*"), 0)
        expect(cur.read_varint).to eq(300)
      end

      it "advances pos past the varint bytes" do
        cur = described_class.new([0xAC, 0x02, 0x00].pack("C*"), 0)
        cur.read_varint
        expect(cur.pos).to eq(2)
      end

      it "raises Error when truncated mid-varint" do
        cur = described_class.new([0x80].pack("C"), 0)  # MSB set, no continuation
        expect { cur.read_varint }.to raise_error(OtlpProtobufDecoder::Error, /truncated/)
      end
    end

    describe "#read_fixed64_bytes" do
      it "reads 8 bytes and advances pos by 8" do
        buf = [1_000_000_000_000_000_000].pack("Q<")
        cur = described_class.new(buf, 0)
        result = cur.read_fixed64_bytes
        expect(result.unpack1("Q<")).to eq(1_000_000_000_000_000_000)
        expect(cur.pos).to eq(8)
      end

      it "raises Error when fewer than 8 bytes remain" do
        cur = described_class.new("\x00\x01\x02".b, 0)
        expect { cur.read_fixed64_bytes }.to raise_error(OtlpProtobufDecoder::Error, /truncated/)
      end
    end

    describe "#sub_cursor" do
      it "reads length then slices that many bytes into a new Cursor at pos 0" do
        # varint 3 followed by "abc"
        buf = pb_varint(3) + "abc".b
        cur = described_class.new(buf, 0)
        sub = cur.sub_cursor
        expect(sub.buf).to eq("abc".b)
        expect(sub.pos).to eq(0)
        expect(cur.pos).to eq(buf.bytesize)
      end
    end

    describe "#skip_field" do
      it "skips a varint (wire_type 0)" do
        buf = pb_varint(300)
        cur = described_class.new(buf, 0)
        cur.skip_field(0)
        expect(cur.pos).to eq(buf.bytesize)
      end

      it "skips a fixed64 (wire_type 1)" do
        buf = [0].pack("Q<")
        cur = described_class.new(buf, 0)
        cur.skip_field(1)
        expect(cur.pos).to eq(8)
      end

      it "skips a length-delimited field (wire_type 2)" do
        buf = pb_varint(3) + "xyz".b
        cur = described_class.new(buf, 0)
        cur.skip_field(2)
        expect(cur.pos).to eq(buf.bytesize)
      end
    end
  end

  # ── AnyValue and KeyValue ─────────────────────────────────────────────────────

  describe ".decode_traces — AnyValue types in span attributes" do
    def span_with_attr(any_value_bytes)
      trace_id_bytes = ["a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6"].pack("H*")
      span_id_bytes  = ["aaaa0000aaaa0000"].pack("H*")

      span = pb_len(1, trace_id_bytes) +
             pb_len(2, span_id_bytes) +
             pb_str(5, "openclaw.request") +
             pb_fixed64(7, 1_000_000_000_000_000_000) +
             pb_fixed64(8, 2_000_000_000_000_000_000) +
             pb_len(9, kv("the_key", any_value_bytes))  # attributes field 9

      resource = pb_len(1, pb_len(1, kv("openclaw.session.key", av_string("agent"))))
      scope    = pb_len(2, pb_len(2, span))
      pb_len(1, resource + scope)
    end

    def decoded_attr(any_value_bytes)
      result = described_class.decode_traces(span_with_attr(any_value_bytes))
      result.dig("resourceSpans", 0, "scopeSpans", 0, "spans", 0, "attributes", 0)
    end

    it "decodes stringValue" do
      attr = decoded_attr(av_string("hello"))
      expect(attr).to eq({ "key" => "the_key", "value" => { "stringValue" => "hello" } })
    end

    it "decodes boolValue true" do
      attr = decoded_attr(av_bool(true))
      expect(attr).to eq({ "key" => "the_key", "value" => { "boolValue" => true } })
    end

    it "decodes boolValue false" do
      attr = decoded_attr(av_bool(false))
      expect(attr).to eq({ "key" => "the_key", "value" => { "boolValue" => false } })
    end

    it "decodes intValue" do
      attr = decoded_attr(av_int(42))
      expect(attr).to eq({ "key" => "the_key", "value" => { "intValue" => 42 } })
    end

    it "decodes doubleValue" do
      attr = decoded_attr(av_double(3.14))
      value = attr.dig("value", "doubleValue")
      expect(value).to be_within(0.0001).of(3.14)
    end
  end
end
