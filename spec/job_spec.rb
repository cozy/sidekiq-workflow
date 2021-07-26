RSpec.describe Sidekiq::Workflow::Job do
  before(:each) do
    Sidekiq::Worker.clear_all
  end

  it 'must allow sidekiq configuration per job' do
    class TestJob1
      include Sidekiq::Workflow::Worker
      sidekiq_options queue: :test_1, retry: 1
      sidekiq_retry_in { 10 }

      def perform(...) end
    end

    class TestJob2
      include Sidekiq::Workflow::Worker
      sidekiq_options queue: :test_2, retry: 2
      sidekiq_retry_in { 20 }

      def perform(...) end
    end

    class TestWorkflow < Sidekiq::Workflow
      def configure
        job TestJob1
        job TestJob2
      end
    end

    TestWorkflow.start!
    expect(TestJob1.jobs.size).to eq 1
    job1 = TestJob1.jobs.first
    expect(job1).to include 'retry' => 1, 'queue' => 'test_1'
    queue1 = Sidekiq::Queues['test_1']
    expect(queue1.size).to eq 1
    job1 = queue1.first
    expect(job1).to include 'class' => 'TestJob1'

    expect(TestJob2.jobs.size).to eq 1
    job2 = TestJob2.jobs.first
    expect(job2).to include 'retry' => 2, 'queue' => 'test_2'
    queue2 = Sidekiq::Queues['test_2']
    expect(queue2.size).to eq 1
    job2 = queue2.first
    expect(job2).to include 'class' => 'TestJob2'
  end

  describe '#status' do
    it 'must have the correct state given timestamp' do
      job = described_class.create OpenStruct.new(id: ''), Class
      expect(job.status).to eq :pending
      job.enqueued_at = Time.now
      expect(job.status).to eq :enqueued
      job.started_at = Time.now
      expect(job.status).to eq :started
      job.finished_at = Time.now
      expect(job.status).to eq :finished
      job.error_at = Time.now
      expect(job.status).to eq :error
      job.failed_at = Time.now
      expect(job.status).to eq :failed
    end
  end
end
