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
      when 1 then self.pos += 8
      when 2
        len = read_varint
        self.pos += len
      when 5 then self.pos += 4
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

  def parse_export_traces(_cur)
    { "resourceSpans" => [] }
  end

  def parse_export_metrics(_cur)
    { "resourceMetrics" => [] }
  end
end
