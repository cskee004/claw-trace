# frozen_string_literal: true

# Pure-Ruby decoder for OTLP proto3 binary payloads.
#
# Implements only the wire-format fields needed for ExportTraceServiceRequest
# and ExportMetricsServiceRequest. No gems, no native extensions.
#
# Output is structurally identical to what OtlpNormalizer and MetricsNormalizer
# accept — same camelCase keys, same nesting, same value types.
#
# Usage:
#   hash = OtlpProtobufDecoder.decode_traces(binary_string)
#   hash = OtlpProtobufDecoder.decode_metrics(binary_string)
#
# Raises OtlpProtobufDecoder::Error on truncated or malformed binary.
# Unknown fields are skipped silently.
class OtlpProtobufDecoder
  Error = Class.new(StandardError)

  # Stateful cursor for sequential binary reading.
  # All methods raise OtlpProtobufDecoder::Error on truncation.
  Cursor = Struct.new(:buf, :pos) do
    def read_varint
      result, shift = 0, 0
      loop do
        raise OtlpProtobufDecoder::Error, "truncated protobuf message" if pos >= buf.bytesize
        byte = buf.getbyte(pos)
        self.pos += 1
        result |= (byte & 0x7F) << shift
        return result if (byte & 0x80).zero?

        shift += 7
      end
    end

    def read_fixed64_bytes
      raise OtlpProtobufDecoder::Error, "truncated protobuf message" if pos + 8 > buf.bytesize

      bytes = buf.byteslice(pos, 8)
      self.pos += 8
      bytes
    end

    def read_fixed32_bytes
      raise OtlpProtobufDecoder::Error, "truncated protobuf message" if pos + 4 > buf.bytesize

      bytes = buf.byteslice(pos, 4)
      self.pos += 4
      bytes
    end

    def read_bytes(len)
      raise OtlpProtobufDecoder::Error, "truncated protobuf message" if pos + len > buf.bytesize

      bytes = buf.byteslice(pos, len)
      self.pos += len
      bytes
    end

    # Returns [field_number, wire_type] or nil at end of buffer.
    def read_tag
      return nil if pos >= buf.bytesize

      tag = read_varint
      [tag >> 3, tag & 0x7]
    end

    def skip_field(wire_type)
      case wire_type
      when 0 then read_varint
      when 1 then read_fixed64_bytes
      when 2
        len = read_varint
        read_bytes(len)
      when 5 then read_fixed32_bytes
      else raise OtlpProtobufDecoder::Error, "unknown wire type #{wire_type}"
      end
    end

    # Reads length-delimited bytes and returns a new sub-Cursor at pos 0.
    def sub_cursor
      len = read_varint
      Cursor.new(read_bytes(len), 0)
    end
  end

  def self.decode_traces(binary)
    new.send(:parse_export_traces, Cursor.new(binary.b, 0))
  end

  def self.decode_metrics(binary)
    new.send(:parse_export_metrics, Cursor.new(binary.b, 0))
  end

  private

  # ── Shared ────────────────────────────────────────────────────────────────────

  def parse_any_value(cur)
    result = {}
    while (field, wire = cur.read_tag)
      case [field, wire]
      when [1, 2] then result["stringValue"] = cur.sub_cursor.buf.force_encoding("UTF-8")
      when [2, 0] then result["boolValue"] = cur.read_varint != 0
      when [3, 0] then result["intValue"] = cur.read_varint
      when [4, 1] then result["doubleValue"] = cur.read_fixed64_bytes.unpack1("E")
      else cur.skip_field(wire)
      end
    end
    result
  end

  def parse_key_value(cur)
    kv = {}
    while (field, wire = cur.read_tag)
      case [field, wire]
      when [1, 2] then kv["key"] = cur.sub_cursor.buf.force_encoding("UTF-8")
      when [2, 2] then kv["value"] = parse_any_value(cur.sub_cursor)
      else cur.skip_field(wire)
      end
    end
    kv
  end

  def parse_resource(cur)
    attributes = []
    while (field, wire = cur.read_tag)
      if field == 1 && wire == 2
        attributes << parse_key_value(cur.sub_cursor)
      else
        cur.skip_field(wire)
      end
    end
    { "attributes" => attributes }
  end

  # ── Traces ────────────────────────────────────────────────────────────────────

  def parse_export_traces(cur)
    resource_spans = []
    while (field, wire = cur.read_tag)
      if field == 1 && wire == 2
        resource_spans << parse_resource_spans(cur.sub_cursor)
      else
        cur.skip_field(wire)
      end
    end
    { "resourceSpans" => resource_spans }
  end

  def parse_resource_spans(cur)
    result = {}
    scope_spans = []
    while (field, wire = cur.read_tag)
      case [field, wire]
      when [1, 2] then result["resource"] = parse_resource(cur.sub_cursor)
      when [2, 2] then scope_spans << parse_scope_spans(cur.sub_cursor)
      else cur.skip_field(wire)
      end
    end
    result["scopeSpans"] = scope_spans
    result
  end

  def parse_scope_spans(cur)
    spans = []
    while (field, wire = cur.read_tag)
      if field == 2 && wire == 2
        spans << parse_span(cur.sub_cursor)
      else
        cur.skip_field(wire)
      end
    end
    { "spans" => spans }
  end

  def parse_span(cur)
    span = {}
    while (field, wire = cur.read_tag)
      case [field, wire]
      when [1, 2]  then span["traceId"] = cur.sub_cursor.buf.unpack1("H*")
      when [2, 2]  then span["spanId"] = cur.sub_cursor.buf.unpack1("H*")
      when [4, 2]
        hex = cur.sub_cursor.buf.unpack1("H*")
        span["parentSpanId"] = hex unless hex.empty?
      when [5, 2]  then span["name"] = cur.sub_cursor.buf.force_encoding("UTF-8")
      when [6, 0]  then cur.read_varint  # kind — not used by normalizer
      when [7, 1]  then span["startTimeUnixNano"] = cur.read_fixed64_bytes.unpack1("Q<").to_s
      when [8, 1]  then span["endTimeUnixNano"] = cur.read_fixed64_bytes.unpack1("Q<").to_s
      when [9, 2]  then (span["attributes"] ||= []) << parse_key_value(cur.sub_cursor)
      when [15, 2] then span["status"] = parse_status(cur.sub_cursor)
      when [16, 5] then cur.read_fixed32_bytes  # flags — skip
      else cur.skip_field(wire)
      end
    end
    span
  end

  def parse_status(cur)
    status = {}
    while (field, wire = cur.read_tag)
      case [field, wire]
      when [2, 2] then status["message"] = cur.sub_cursor.buf.force_encoding("UTF-8")
      when [3, 0] then status["code"] = cur.read_varint
      else cur.skip_field(wire)
      end
    end
    status
  end

  # ── Metrics (stub — implemented in Task 4) ────────────────────────────────────

  def parse_export_metrics(_cur)
    { "resourceMetrics" => [] }
  end
end
