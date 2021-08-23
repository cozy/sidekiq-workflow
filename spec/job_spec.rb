module JobSpec
  RSpec.describe Sidekiq::Workflow::Job do
    before(:each) do
      Sidekiq::Worker.clear_all
    end

    TestJob1 = Class.new do
      include Sidekiq::Workflow::Worker
      sidekiq_options queue: :test_1, retry: 1
      sidekiq_retry_in { 10 }

      def perform(...) end
    end

    TestJob2 = Class.new do
      include Sidekiq::Workflow::Worker
      sidekiq_options queue: :test_2, retry: 2
      sidekiq_retry_in { 20 }

      def perform(...) end
    end

    TestAbortingJob = Class.new do
      include Sidekiq::Workflow::Worker

      def perform
        self.abort! 'some message'
      end
    end

    it 'must allow sidekiq configuration per job' do
      testWorkflow = Class.new Sidekiq::Workflow do
        def configure
          job TestJob1
          job TestJob2
        end
      end

      testWorkflow.start!
      expect(TestJob1.jobs.size).to eq 1
      job1 = TestJob1.jobs.first
      expect(job1).to include 'retry' => 1, 'queue' => 'test_1'
      queue1 = Sidekiq::Queues['test_1']
      expect(queue1.size).to eq 1
      job1 = queue1.first
      expect(job1).to include 'class' => 'JobSpec::TestJob1'

      expect(TestJob2.jobs.size).to eq 1
      job2 = TestJob2.jobs.first
      expect(job2).to include 'retry' => 2, 'queue' => 'test_2'
      queue2 = Sidekiq::Queues['test_2']
      expect(queue2.size).to eq 1
      job2 = queue2.first
      expect(job2).to include 'class' => 'JobSpec::TestJob2'
    end

    describe '#status' do
      it 'must have the correct state given timestamp' do
        job = described_class.create OpenStruct.new(id: ''), Class
        expect(job.status).to eq :pending
        job.enqueued_at = Time.now
        expect(job.status).to eq :enqueued
        job.started_at = Time.now
        expect(job.status).to eq :started
        job.error_at = Time.now
        expect(job.status).to eq :error
        job.finished_at = Time.now
        expect(job.status).to eq :finished
        job.failed_at = Time.now
        expect(job.status).to eq :failed
      end
    end

    describe '#state' do
      it 'must flag the job as finished in case of success' do
        class TestJob
          include Sidekiq::Workflow::Worker

          def perform; end
        end

        workflow = Sidekiq::Workflow.new Class, 'workflow_1'
        job      = Sidekiq::Workflow::Job.create workflow, TestJob.name
        allow(Sidekiq::Workflow::Job).to receive(:find).with(job.id) { job }
        expect(job.enqueued_at).to be_nil
        expect(job.finished_at).to be_nil
        expect(job.error_at).to be_nil
        expect(job.failed_at).to be_nil

        job.perform
        expect(job.enqueued_at).to_not be_nil
        expect(job.finished_at).to be_nil
        expect(job.error_at).to be_nil
        expect(job.failed_at).to be_nil

        TestJob.perform_one
        expect(job.enqueued_at).to_not be_nil
        expect(job.finished_at).to_not be_nil
        expect(job.error_at).to be_nil
        expect(job.failed_at).to be_nil
      end

      it 'must flag the job as errored in case of error' do
        class TestJob
          include Sidekiq::Workflow::Worker

          def self.message=(message)
            @@message = message
          end

          def perform
            raise @@message if @@message
          end
        end

        workflow = Sidekiq::Workflow.new Class, 'workflow_1'
        job      = Sidekiq::Workflow::Job.create workflow, TestJob.name
        allow(Sidekiq::Workflow::Job).to receive(:find).with(job.id) { job }

        job.perform
        expect(job.error_at).to be_nil
        expect(job.errors).to be_empty
        expect(job.finished_at).to be_nil
        TestJob.message = 'perform_error'
        Timecop.freeze do |now|
          expect { TestJob.perform_one }.to raise_error 'perform_error'
          expect(job.error_at).to eq now
          expect(job.errors).to eq([{ date: now, error: 'perform_error' }])
        end
        expect(job.finished_at).to be_nil

        job.perform
        TestJob.message = nil
        TestJob.perform_one
        expect(job.error_at).to_not be_nil
        expect(job.finished_at).to_not be_nil
      end
    end

    describe '#abort!' do
      it 'must cancel the job' do
        workflow = Sidekiq::Workflow.new Class, 'workflow_1'
        job      = Sidekiq::Workflow::Job.create workflow, TestAbortingJob.name
        allow(Sidekiq::Workflow::Job).to receive(:find).with(job.id) { job }
        expect(job.enqueued_at).to be_nil
        expect(job.finished_at).to be_nil
        expect(job.error_at).to be_nil
        expect(job.failed_at).to be_nil

        job.perform
        expect(job.enqueued_at).to_not be_nil
        expect(job.finished_at).to be_nil
        expect(job.error_at).to be_nil
        expect(job.failed_at).to be_nil

        TestAbortingJob.perform_one
        expect(job.enqueued_at).to_not be_nil
        expect(job.finished_at).to be_nil
        expect(job.error_at).to_not be_nil
        expect(job.failed_at).to_not be_nil
      end
    end
  end
end
