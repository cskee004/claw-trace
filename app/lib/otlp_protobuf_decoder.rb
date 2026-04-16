# frozen_string_literal: true

# Pure-Ruby decoder for OTLP proto3 binary payloads.
#
# Implements only the wire-format fields needed for ExportTraceServiceRequest,
# ExportMetricsServiceRequest, and ExportLogsServiceRequest. No gems, no native extensions.
#
# Output is structurally identical to what OtlpNormalizer, MetricsNormalizer, and
# LogsNormalizer accept — same camelCase keys, same nesting, same value types.
#
# Usage:
#   hash = OtlpProtobufDecoder.decode_traces(binary_string)
#   hash = OtlpProtobufDecoder.decode_metrics(binary_string)
#   hash = OtlpProtobufDecoder.decode_logs(binary_string)
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

  def self.decode_logs(binary)
    new.send(:parse_export_logs, Cursor.new(binary.b, 0))
  end

  private

  # ============================================================================
  # PATTERNS GUIDE — for me, not you. This is a reference for how to read the code below, not a comment on
  # the code itself. The methods below are straightforward implementations of the
  # proto3 wire format; they don't need comments, but I do.
  # ============================================================================
  #
  # This decoder translates raw proto3 binary into Ruby hashes that look exactly
  # like the JSON OTLP format. Because proto3 messages share the same binary
  # encoding rules everywhere, the same small set of patterns appears over and
  # over throughout this file. Learn them once and you can read any method here.
  #
  # ── Pattern 1: The Parse Loop ───────────────────────────────────────────────
  #
  # Nearly every `parse_*` method has this skeleton:
  #
  #   def parse_something(cur)
  #     result = {}                          # 1. start with an empty container
  #     while (field, wire = cur.read_tag)   # 2. read next field tag (nil = done)
  #       case [field, wire]                 # 3. dispatch on [field_number, wire_type]
  #       when [1, 2] then result["foo"] = ...
  #       when [3, 0] then result["bar"] = ...
  #       else cur.skip_field(wire)          # 4. skip ANYTHING we don't recognise
  #       end
  #     end
  #     result                               # 5. return the populated hash
  #   end
  #
  # `field` is the proto field number (matches the `.proto` schema definition).
  # `wire` is the wire type — a 3-bit encoding hint (see Pattern 3 below).
  # The `else cur.skip_field(wire)` is critical: proto3 allows senders to add new
  # fields at any time; silently skipping unknown ones keeps the decoder forwards-
  # compatible without ever raising an error.
  #
  # ── Pattern 2: Collect-Into-Array (a parse-loop variant) ────────────────────
  #
  # When a proto message only contains one repeated sub-message field, the parse
  # loop simplifies to:
  #
  #   def parse_container(cur)
  #     items = []
  #     while (field, wire = cur.read_tag)
  #       if field == N && wire == 2
  #         items << parse_item(cur.sub_cursor)   # accumulate into an array
  #       else
  #         cur.skip_field(wire)
  #       end
  #     end
  #     { "items" => items }
  #   end
  #
  # Examples in this file: `parse_export_traces`, `parse_scope_spans`,
  # `parse_sum`, `parse_histogram`, `parse_resource`.
  #
  # ── Pattern 3: Wire Type → Reader Method ────────────────────────────────────
  #
  # The second element of `[field, wire]` tells you HOW the value was encoded.
  # Only four wire types appear in OTLP payloads:
  #
  #   wire == 0  →  read_varint            integers, booleans, enums
  #   wire == 1  →  read_fixed64_bytes     64-bit timestamps, doubles
  #   wire == 2  →  sub_cursor  (or .buf)  strings, bytes, nested messages,
  #                                         and packed repeated fields
  #   wire == 5  →  read_fixed32_bytes     32-bit values (rare; usually skipped)
  #
  # That pairing is how you read `[field, wire]` tuples at a glance: the first
  # number identifies WHAT to read; the second tells you HOW to read it.
  #
  # ── Pattern 4: Nested Message Decoding via sub_cursor ───────────────────────
  #
  # When wire == 2 and the field contains another message (not a plain string),
  # the convention is:
  #
  #   when [N, 2] then result["child"] = parse_child(cur.sub_cursor)
  #
  # `sub_cursor` reads the length-prefix from the outer cursor and returns a
  # brand-new Cursor that sees only the bytes of that nested message. The inner
  # parse method then runs its own parse loop against those bytes, completely
  # independent of the outer stream. This is how the tree of proto messages maps
  # to a tree of Ruby hashes.
  #
  # ── Pattern 5: Lazy Array Accumulation for Repeated Fields ──────────────────
  #
  # Some fields (like `attributes`) can appear multiple times in the same message
  # — proto3 represents repetition by emitting the same field number again rather
  # than wrapping everything in one block. The pattern for collecting these is:
  #
  #   when [N, 2] then (result["attributes"] ||= []) << parse_key_value(cur.sub_cursor)
  #
  # `||= []` initialises the array only on the first occurrence; `<<` appends
  # every subsequent one. You'll see this on `attributes` fields in `parse_span`,
  # `parse_number_data_point`, `parse_histogram_data_point`, and `parse_log_record`.
  #
  # ── Pattern 6: Packed Repeated Scalar Fields ─────────────────────────────────
  #
  # Proto3 packs repeated primitive values (numbers, floats) into a single
  # length-delimited blob instead of emitting one field tag per value. To unpack
  # them, get a sub-cursor and loop until its bytes are exhausted:
  #
  #   when [N, 2]
  #     inner = cur.sub_cursor
  #     values = []
  #     values << inner.read_varint while inner.pos < inner.buf.bytesize
  #     result["values"] = values
  #
  # Examples: `bucketCounts` (varints) and `explicitBounds` (doubles) in
  # `parse_histogram_data_point`.
  #
  # ── Value Extraction Quick-Reference ────────────────────────────────────────
  #
  # Once you have the raw bytes, the unpack format string tells you the type:
  #
  #   cur.sub_cursor.buf.force_encoding("UTF-8")   → UTF-8 string
  #   cur.sub_cursor.buf.unpack1("H*")             → hex string  (traceId, spanId)
  #   cur.read_fixed64_bytes.unpack1("Q<")         → uint64 integer (timestamps)
  #   cur.read_fixed64_bytes.unpack1("E")          → 64-bit double (floats)
  #   cur.read_fixed64_bytes.unpack1("q<")         → int64 signed integer
  #   cur.read_varint != 0                         → boolean (varint 0 = false)
  #
  # Timestamps always end in `.to_s` because the OTLP JSON spec represents
  # nanosecond counters as strings to avoid JavaScript integer overflow.
  #
  # ============================================================================

  # ── Shared ────────────────────────────────────────────────────────────────────

  # Decodes an OTLP AnyValue message. Only scalar types (string, bool, int, double)
  # are extracted. Non-scalar types (arrayValue field 5, kvlistValue field 6,
  # bytesValue field 7) are skipped at the wire level via skip_field — they produce
  # no key in the result hash. OpenClaw attributes were validated as scalar-only
  # on 2026-04-10, so silent omission is intentional, not a gap.
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
      when [9, 2]  then (span["attributes"] ||= []) << parse_key_value(cur.sub_cursor)  # Pattern 5 — lazy array accumulation for a repeated field
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

  # ── Metrics ───────────────────────────────────────────────────────────────────

  def parse_export_metrics(cur)
    resource_metrics = []
    while (field, wire = cur.read_tag)
      if field == 1 && wire == 2
        resource_metrics << parse_resource_metrics(cur.sub_cursor)
      else
        cur.skip_field(wire)
      end
    end
    { "resourceMetrics" => resource_metrics }
  end

  def parse_resource_metrics(cur)
    result = {}
    scope_metrics = []
    while (field, wire = cur.read_tag)
      case [field, wire]
      when [1, 2] then result["resource"] = parse_resource(cur.sub_cursor)
      when [2, 2] then scope_metrics << parse_scope_metrics(cur.sub_cursor)
      else cur.skip_field(wire)
      end
    end
    result["scopeMetrics"] = scope_metrics
    result
  end

  def parse_scope_metrics(cur)
    metrics = []
    while (field, wire = cur.read_tag)
      # field 3: ScopeMetrics.metrics (OTLP ≥0.10 / new format)
      # field 2: InstrumentationLibraryMetrics.metrics (old OTEL SDK format)
      if (field == 3 || field == 2) && wire == 2
        metrics << parse_metric(cur.sub_cursor)
      else
        cur.skip_field(wire)
      end
    end
    { "metrics" => metrics }
  end

  def parse_metric(cur)
    metric = {}
    while (field, wire = cur.read_tag)
      case [field, wire]
      when [1, 2] then metric["name"] = cur.sub_cursor.buf.force_encoding("UTF-8")
      when [5, 2] then metric["gauge"] = parse_gauge(cur.sub_cursor)
      when [7, 2] then metric["sum"] = parse_sum(cur.sub_cursor)
      when [9, 2] then metric["histogram"] = parse_histogram(cur.sub_cursor)
      else cur.skip_field(wire)
      end
    end
    metric
  end

  def parse_gauge(cur)
    data_points = []
    while (field, wire = cur.read_tag)
      if field == 1 && wire == 2
        data_points << parse_number_data_point(cur.sub_cursor)
      else
        cur.skip_field(wire)
      end
    end
    { "dataPoints" => data_points }
  end

  def parse_sum(cur)
    data_points = []
    while (field, wire = cur.read_tag)
      if field == 1 && wire == 2
        data_points << parse_number_data_point(cur.sub_cursor)
      else
        cur.skip_field(wire)
      end
    end
    { "dataPoints" => data_points }
  end

  def parse_number_data_point(cur)
    dp = {}
    while (field, wire = cur.read_tag)
      case [field, wire]
      when [2, 1] then dp["startTimeUnixNano"] = cur.read_fixed64_bytes.unpack1("Q<").to_s
      when [3, 1] then dp["timeUnixNano"] = cur.read_fixed64_bytes.unpack1("Q<").to_s
      when [4, 1] then dp["asDouble"] = cur.read_fixed64_bytes.unpack1("E")
      when [6, 1] then dp["asInt"] = cur.read_fixed64_bytes.unpack1("q<")  # sfixed64 signed
      when [7, 2] then (dp["attributes"] ||= []) << parse_key_value(cur.sub_cursor)
      else cur.skip_field(wire)
      end
    end
    dp
  end

  def parse_histogram(cur)
    data_points = []
    while (field, wire = cur.read_tag)
      if field == 1 && wire == 2
        data_points << parse_histogram_data_point(cur.sub_cursor)
      else
        cur.skip_field(wire)
      end
    end
    { "dataPoints" => data_points }
  end

  def parse_histogram_data_point(cur)
    dp = {}
    while (field, wire = cur.read_tag)
      case [field, wire]
      when [2, 1] then dp["startTimeUnixNano"] = cur.read_fixed64_bytes.unpack1("Q<").to_s
      when [3, 1] then dp["timeUnixNano"] = cur.read_fixed64_bytes.unpack1("Q<").to_s
      when [6, 0] then dp["count"] = cur.read_varint           # uint64 — varint wire type
      when [7, 1] then dp["sum"] = cur.read_fixed64_bytes.unpack1("E")
      when [8, 2]  # Pattern 6 — packed repeated varints; loop until sub-cursor is exhausted
        inner = cur.sub_cursor
        counts = []
        counts << inner.read_varint while inner.pos < inner.buf.bytesize
        dp["bucketCounts"] = counts
      when [9, 2] then (dp["attributes"] ||= []) << parse_key_value(cur.sub_cursor)
      when [10, 2]
        inner = cur.sub_cursor
        bounds = []
        bounds << inner.read_fixed64_bytes.unpack1("E") while inner.pos < inner.buf.bytesize
        dp["explicitBounds"] = bounds
      when [11, 1] then dp["min"] = cur.read_fixed64_bytes.unpack1("E")
      when [12, 1] then dp["max"] = cur.read_fixed64_bytes.unpack1("E")
      else cur.skip_field(wire)
      end
    end
    dp
  end

  # ── Logs ──────────────────────────────────────────────────────────────────────

  def parse_export_logs(cur)
    resource_logs = []
    while (field, wire = cur.read_tag)
      if field == 1 && wire == 2
        resource_logs << parse_resource_logs(cur.sub_cursor)
      else
        cur.skip_field(wire)
      end
    end
    { "resourceLogs" => resource_logs }
  end

  def parse_resource_logs(cur)
    result = {}
    scope_logs = []
    while (field, wire = cur.read_tag)
      case [field, wire]
      when [1, 2] then result["resource"] = parse_resource(cur.sub_cursor)
      when [2, 2] then scope_logs << parse_scope_logs(cur.sub_cursor)
      else cur.skip_field(wire)
      end
    end
    result["scopeLogs"] = scope_logs
    result
  end

  def parse_scope_logs(cur)
    log_records = []
    while (field, wire = cur.read_tag)
      if field == 2 && wire == 2
        log_records << parse_log_record(cur.sub_cursor)
      else
        cur.skip_field(wire)
      end
    end
    { "logRecords" => log_records }
  end

  def parse_log_record(cur)
    lr = {}
    while (field, wire = cur.read_tag)
      case [field, wire]
      when [1, 1]  then lr["timeUnixNano"]   = cur.read_fixed64_bytes.unpack1("Q<").to_s
      when [2, 0]  then lr["severityNumber"] = cur.read_varint
      when [3, 2]  then lr["severityText"]   = cur.sub_cursor.buf.force_encoding("UTF-8")
      when [5, 2]  then lr["body"]           = parse_any_value(cur.sub_cursor)
      when [6, 2]  then (lr["attributes"] ||= []) << parse_key_value(cur.sub_cursor)
      when [9, 2]
        hex = cur.sub_cursor.buf.unpack1("H*")
        lr["traceId"] = hex unless hex.empty?
      when [10, 2]
        hex = cur.sub_cursor.buf.unpack1("H*")
        lr["spanId"] = hex unless hex.empty?
      else cur.skip_field(wire)
      end
    end
    lr
  end
end
