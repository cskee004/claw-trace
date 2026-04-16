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

  describe ".decode_traces" do
    let(:trace_id_bytes)  { ["a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6"].pack("H*") }  # 16 bytes
    let(:span_id_bytes)   { ["aaaa0000aaaa0000"].pack("H*") }                    # 8 bytes
    let(:parent_id_bytes) { ["bbbb0000bbbb0000"].pack("H*") }                    # 8 bytes

    def minimal_span_bytes
      pb_len(1, trace_id_bytes) +
        pb_len(2, span_id_bytes) +
        pb_str(5, "openclaw.request") +
        pb_fixed64(7, 1_000_000_000_000_000_000) +
        pb_fixed64(8, 2_000_000_000_000_000_000)
    end

    def wrap_in_export_traces(span_bytes, session_key: "test-agent")
      resource = pb_len(1, pb_len(1, kv("openclaw.session.key", av_string(session_key))))
      scope    = pb_len(2, pb_len(2, span_bytes))
      pb_len(1, resource + scope)
    end

    let(:binary) { wrap_in_export_traces(minimal_span_bytes) }

    it "returns a hash with resourceSpans key" do
      result = described_class.decode_traces(binary)
      expect(result).to have_key("resourceSpans")
    end

    it "decodes traceId as lowercase hex string" do
      result = described_class.decode_traces(binary)
      expect(result.dig("resourceSpans", 0, "scopeSpans", 0, "spans", 0, "traceId"))
        .to eq("a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6")
    end

    it "decodes spanId as lowercase hex string" do
      result = described_class.decode_traces(binary)
      expect(result.dig("resourceSpans", 0, "scopeSpans", 0, "spans", 0, "spanId"))
        .to eq("aaaa0000aaaa0000")
    end

    it "decodes startTimeUnixNano as a decimal nanosecond string" do
      result = described_class.decode_traces(binary)
      expect(result.dig("resourceSpans", 0, "scopeSpans", 0, "spans", 0, "startTimeUnixNano"))
        .to eq("1000000000000000000")
    end

    it "decodes parentSpanId as hex when present" do
      span = minimal_span_bytes + pb_len(4, parent_id_bytes)
      result = described_class.decode_traces(wrap_in_export_traces(span))
      expect(result.dig("resourceSpans", 0, "scopeSpans", 0, "spans", 0, "parentSpanId"))
        .to eq("bbbb0000bbbb0000")
    end

    it "omits parentSpanId key when field is absent" do
      result = described_class.decode_traces(binary)
      span = result.dig("resourceSpans", 0, "scopeSpans", 0, "spans", 0)
      expect(span).not_to have_key("parentSpanId")
    end

    it "decodes span name" do
      result = described_class.decode_traces(binary)
      expect(result.dig("resourceSpans", 0, "scopeSpans", 0, "spans", 0, "name"))
        .to eq("openclaw.request")
    end

    it "decodes status code 2 (ERROR)" do
      status_bytes = pb_int(3, 2)  # Status { code = 2 }
      span = minimal_span_bytes + pb_len(15, status_bytes)
      result = described_class.decode_traces(wrap_in_export_traces(span))
      expect(result.dig("resourceSpans", 0, "scopeSpans", 0, "spans", 0, "status", "code"))
        .to eq(2)
    end

    it "decodes resource attributes" do
      result = described_class.decode_traces(binary)
      attrs = result.dig("resourceSpans", 0, "resource", "attributes")
      expect(attrs).to include({ "key" => "openclaw.session.key", "value" => { "stringValue" => "test-agent" } })
    end

    it "returns { 'resourceSpans' => [] } for empty binary" do
      expect(described_class.decode_traces("")).to eq({ "resourceSpans" => [] })
    end

    it "raises Error on truncated varint" do
      expect { described_class.decode_traces("\x8A".b) }.to raise_error(OtlpProtobufDecoder::Error, /truncated/)
    end

    it "raises Error on truncated length-delimited field" do
      # Tag for field 1 wire 2, then length 100, but only 3 bytes of data
      buf = pb_tag(1, 2) + pb_varint(100) + "abc".b
      expect { described_class.decode_traces(buf) }.to raise_error(OtlpProtobufDecoder::Error, /truncated/)
    end
  end

  describe ".decode_metrics" do
    def wrap_in_export_metrics(metric_bytes)
      scope = pb_len(3, metric_bytes)   # ScopeMetrics.metrics = field 3
      pb_len(1, pb_len(2, scope))       # ResourceMetrics.scope_metrics = field 2, ExportMetricsServiceRequest.resource_metrics = field 1
    end

    # ── Sum metric ────────────────────────────────────────────────────────────

    describe "sum metric with asInt" do
      let(:dp_bytes) do
        pb_fixed64(2, 1_712_345_678_000_000_000) +  # startTimeUnixNano
          pb_fixed64(3, 1_712_345_678_500_000_000) +  # timeUnixNano
          pb_sfixed64(6, 1200)                          # asInt (sfixed64, wire_type 1)
      end

      let(:metric_bytes) do
        pb_str(1, "gen_ai.client.token.usage") +  # Metric.name = field 1
          pb_len(7, pb_len(1, dp_bytes))            # Metric.sum = field 7, Sum.data_points = field 1
      end

      let(:binary) { wrap_in_export_metrics(metric_bytes) }

      it "decodes the metric name" do
        result = described_class.decode_metrics(binary)
        expect(result.dig("resourceMetrics", 0, "scopeMetrics", 0, "metrics", 0, "name"))
          .to eq("gen_ai.client.token.usage")
      end

      it "decodes sum dataPoint with asInt" do
        result = described_class.decode_metrics(binary)
        dp = result.dig("resourceMetrics", 0, "scopeMetrics", 0, "metrics", 0, "sum", "dataPoints", 0)
        expect(dp["asInt"]).to eq(1200)
      end

      it "decodes timeUnixNano as a decimal string" do
        result = described_class.decode_metrics(binary)
        dp = result.dig("resourceMetrics", 0, "scopeMetrics", 0, "metrics", 0, "sum", "dataPoints", 0)
        expect(dp["timeUnixNano"]).to eq("1712345678500000000")
      end
    end

    describe "sum metric with asDouble" do
      let(:dp_bytes) do
        pb_fixed64(3, 1_712_345_678_500_000_000) +  # timeUnixNano
          pb_fixed64(4, 99.5)                           # asDouble (double field, wire_type 1)
      end

      let(:metric_bytes) do
        pb_str(1, "gen_ai.client.token.usage") +
          pb_len(7, pb_len(1, dp_bytes))
      end

      it "decodes asDouble" do
        result = described_class.decode_metrics(wrap_in_export_metrics(metric_bytes))
        dp = result.dig("resourceMetrics", 0, "scopeMetrics", 0, "metrics", 0, "sum", "dataPoints", 0)
        expect(dp["asDouble"]).to be_within(0.001).of(99.5)
      end
    end

    # ── Histogram metric ──────────────────────────────────────────────────────

    describe "histogram metric" do
      let(:dp_bytes) do
        pb_fixed64(3, 1_712_345_678_500_000_000) +          # timeUnixNano
          pb_int(6, 150) +                                     # count (varint/uint64)
          pb_fixed64(7, 45_230.0) +                           # sum (double)
          pb_packed_varints(8, [10, 40, 60, 30, 10]) +        # bucketCounts
          pb_packed_doubles(10, [100.0, 300.0, 500.0, 700.0]) + # explicitBounds
          pb_fixed64(11, 12.0) +                              # min (double)
          pb_fixed64(12, 890.0)                               # max (double)
      end

      let(:metric_bytes) do
        pb_str(1, "gen_ai.client.operation.duration") +
          pb_len(9, pb_len(1, dp_bytes))  # Metric.histogram = field 9, Histogram.data_points = field 1
      end

      let(:binary) { wrap_in_export_metrics(metric_bytes) }

      def histogram_dp
        described_class.decode_metrics(binary)
          .dig("resourceMetrics", 0, "scopeMetrics", 0, "metrics", 0, "histogram", "dataPoints", 0)
      end

      it "decodes count" do
        expect(histogram_dp["count"]).to eq(150)
      end

      it "decodes sum as a float" do
        expect(histogram_dp["sum"]).to be_within(0.01).of(45_230.0)
      end

      it "decodes bucketCounts as an array" do
        expect(histogram_dp["bucketCounts"]).to eq([10, 40, 60, 30, 10])
      end

      it "decodes explicitBounds as an array of floats" do
        expect(histogram_dp["explicitBounds"]).to eq([100.0, 300.0, 500.0, 700.0])
      end

      it "decodes min" do
        expect(histogram_dp["min"]).to be_within(0.01).of(12.0)
      end

      it "decodes max" do
        expect(histogram_dp["max"]).to be_within(0.01).of(890.0)
      end
    end

    it "returns { 'resourceMetrics' => [] } for empty binary" do
      expect(described_class.decode_metrics("")).to eq({ "resourceMetrics" => [] })
    end
  end

  describe ".decode_logs" do
    let(:trace_id_bytes) { ["a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6"].pack("H*") }
    let(:span_id_bytes)  { ["aaaa0000aaaa0000"].pack("H*") }
    let(:ts_ns)          { 1_712_345_678_500_000_000 }

    def minimal_log_record_bytes
      pb_fixed64(1, ts_ns) +
        pb_int(2, 9) +
        pb_str(3, "INFO") +
        pb_len(5, av_string("agent turn completed")) +
        pb_len(9, trace_id_bytes) +
        pb_len(10, span_id_bytes)
    end

    # Wraps log_record_bytes in ScopeLogs → ResourceLogs → ExportLogsServiceRequest.
    # resource_logs = field 1, scope_logs = field 2, log_records = field 2.
    def wrap_in_export_logs(log_record_bytes)
      scope        = pb_len(2, log_record_bytes)   # ScopeLogs: log_records = field 2
      resource_log = pb_len(2, scope)              # ResourceLogs: scope_logs = field 2
      pb_len(1, resource_log)                      # ExportLogsServiceRequest: resource_logs = field 1
    end

    let(:binary) { wrap_in_export_logs(minimal_log_record_bytes) }

    def log_record(bin = binary)
      described_class.decode_logs(bin)
        .dig("resourceLogs", 0, "scopeLogs", 0, "logRecords", 0)
    end

    it "returns a hash with resourceLogs key" do
      expect(described_class.decode_logs(binary)).to have_key("resourceLogs")
    end

    it "decodes timeUnixNano as a decimal nanosecond string" do
      expect(log_record["timeUnixNano"]).to eq("1712345678500000000")
    end

    it "decodes severityNumber as an integer" do
      expect(log_record["severityNumber"]).to eq(9)
    end

    it "decodes severityText as a string" do
      expect(log_record["severityText"]).to eq("INFO")
    end

    it "decodes body as an AnyValue hash" do
      expect(log_record["body"]).to eq({ "stringValue" => "agent turn completed" })
    end

    it "decodes traceId as a lowercase hex string" do
      expect(log_record["traceId"]).to eq("a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6")
    end

    it "decodes spanId as a lowercase hex string" do
      expect(log_record["spanId"]).to eq("aaaa0000aaaa0000")
    end

    it "omits traceId and spanId keys when fields are absent" do
      bytes_without_ids = pb_fixed64(1, ts_ns) + pb_int(2, 9) + pb_str(3, "WARN")
      lr = log_record(wrap_in_export_logs(bytes_without_ids))
      expect(lr).not_to have_key("traceId")
      expect(lr).not_to have_key("spanId")
    end

    it "returns { 'resourceLogs' => [] } for empty binary" do
      expect(described_class.decode_logs("")).to eq({ "resourceLogs" => [] })
    end

    it "raises Error on truncated binary" do
      expect { described_class.decode_logs("\x8A".b) }
        .to raise_error(OtlpProtobufDecoder::Error, /truncated/)
    end
  end
end
