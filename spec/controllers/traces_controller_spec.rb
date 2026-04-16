require 'rails_helper'

RSpec.describe TracesController, type: :controller do
  def create_trace(trace_id:, status: :success, start_time: Time.utc(2026, 4, 2, 12, 0, 0))
    Trace.create!(
      trace_id:   trace_id,
      agent_id:   "support-agent",
      task_name:  "classify_customer_ticket",
      start_time: start_time,
      status:     status
    )
  end

  def create_span(trace, span_id:, span_type:, timestamp:, metadata: { "info" => "test" })
    Span.create!(
      trace_id:  trace.trace_id,
      span_id:   span_id,
      span_type: span_type,
      timestamp: timestamp,
      agent_id:  trace.agent_id,
      metadata:  metadata
    )
  end

  describe 'GET #index' do
    it 'returns a successful response' do
      get :index
      expect(response).to be_successful
    end

    it 'renders the index template' do
      get :index
      expect(response).to render_template(:index)
    end

    it 'assigns @traces ordered by start_time descending' do
      older = create_trace(trace_id: "a" * 16, start_time: Time.utc(2026, 4, 1, 10, 0, 0))
      newer = create_trace(trace_id: "b" * 16, start_time: Time.utc(2026, 4, 2, 10, 0, 0))

      get :index

      expect(assigns(:traces).first).to eq(newer)
      expect(assigns(:traces).last).to eq(older)
    end

    it 'assigns an empty collection when there are no traces' do
      get :index
      expect(assigns(:traces)).to be_empty
    end

    it 'assigns @durations as a hash of trace_id => milliseconds' do
      trace = create_trace(trace_id: "c" * 16)
      t0 = Time.utc(2026, 4, 2, 12, 0, 0)
      create_span(trace, span_id: "sp1", span_type: "session_event", timestamp: t0)
      create_span(trace, span_id: "sp2", span_type: "span",     timestamp: t0 + 4)

      get :index

      expect(assigns(:durations)[trace.trace_id]).to eq(4000.0)
    end
  end

  describe 'GET #show' do
    let(:trace) { create_trace(trace_id: "d" * 16) }

    context 'when the trace exists' do
      it 'returns a successful response' do
        get :show, params: { id: trace.trace_id }
        expect(response).to be_successful
      end

      it 'renders the show template' do
        get :show, params: { id: trace.trace_id }
        expect(response).to render_template(:show)
      end

      it 'assigns @trace matched by trace_id' do
        get :show, params: { id: trace.trace_id }
        expect(assigns(:trace)).to eq(trace)
      end

      it 'assigns @spans ordered chronologically' do
        t0 = Time.utc(2026, 4, 2, 12, 0, 0)
        s1 = create_span(trace, span_id: "sp1", span_type: "session_event", timestamp: t0)
        s2 = create_span(trace, span_id: "sp2", span_type: "model_call",        timestamp: t0 + 2)
        s3 = create_span(trace, span_id: "sp3", span_type: "span",     timestamp: t0 + 5)

        get :show, params: { id: trace.trace_id }

        expect(assigns(:spans).to_a).to eq([s1, s2, s3])
      end

      it 'assigns @span_latencies keyed by span_id in milliseconds' do
        t0 = Time.utc(2026, 4, 2, 12, 0, 0)
        s1 = create_span(trace, span_id: "sp1", span_type: "session_event", timestamp: t0)
        s2 = create_span(trace, span_id: "sp2", span_type: "model_call",        timestamp: t0 + 3)
        s3 = create_span(trace, span_id: "sp3", span_type: "span",     timestamp: t0 + 7)

        get :show, params: { id: trace.trace_id }

        latencies = assigns(:span_latencies)
        expect(latencies[s1.span_id]).to eq(3000.0)
        expect(latencies[s2.span_id]).to eq(4000.0)
        expect(latencies).not_to have_key(s3.span_id)
      end

      it 'assigns nil @total_duration_ms when there are no spans' do
        get :show, params: { id: trace.trace_id }
        expect(assigns(:total_duration_ms)).to be_nil
      end

      it 'assigns @total_duration_ms as elapsed milliseconds across all spans' do
        t0 = Time.utc(2026, 4, 2, 12, 0, 0)
        create_span(trace, span_id: "sp1", span_type: "session_event", timestamp: t0)
        create_span(trace, span_id: "sp2", span_type: "span",     timestamp: t0 + 9)

        get :show, params: { id: trace.trace_id }

        expect(assigns(:total_duration_ms)).to eq(9000.0)
      end
    end

    context 'when the trace does not exist' do
      it 'raises ActiveRecord::RecordNotFound' do
        expect {
          get :show, params: { id: "nonexistent0000" }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end
