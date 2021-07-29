RSpec.describe Sidekiq::Workflow do
  describe '::start!' do
    class TestJob
      include Sidekiq::Workflow::Worker

      def perform(...) end
    end

    class TestJob1 < TestJob; end

    class TestJob2 < TestJob; end

    class TestJob3 < TestJob; end

    before(:each) do
      Sidekiq::Worker.clear_all
    end

    it 'must handle after job' do
      class TestWorkflow < Sidekiq::Workflow
        def configure
          job1 = job TestJob1
          job TestJob2, after: job1
        end
      end

      TestWorkflow.start!
      expect(TestJob1.jobs.size).to eq 1
      expect(TestJob2.jobs).to be_empty

      TestJob1.perform_one
      expect(TestJob1.jobs).to be_empty
      expect(TestJob2.jobs.size).to eq 1
    end

    it 'must handle before job' do
      class TestWorkflow < Sidekiq::Workflow
        def configure
          job2 = job TestJob2
          job TestJob1, before: job2
        end
      end

      TestWorkflow.start!
      expect(TestJob1.jobs.size).to eq 1
      expect(TestJob2.jobs).to be_empty

      TestJob1.perform_one
      expect(TestJob1.jobs).to be_empty
      expect(TestJob2.jobs.size).to eq 1
    end

    it 'must starts all initial jobs if any' do
      class TestWorkflow < Sidekiq::Workflow
        def configure
          job TestJob1
          job TestJob2
        end
      end

      TestWorkflow.start!
      expect(TestJob1.jobs.size).to eq 1
      expect(TestJob2.jobs.size).to eq 1
    end

    it 'must starts all subsequent jobs if any' do
      class TestWorkflow < Sidekiq::Workflow
        def configure
          job1 = job TestJob1
          job TestJob2, after: job1
          job TestJob3, after: job1
        end
      end

      TestWorkflow.start!
      expect(TestJob1.jobs.size).to eq 1
      expect(TestJob2.jobs).to be_empty
      expect(TestJob3.jobs).to be_empty

      TestJob1.perform_one
      expect(TestJob1.jobs).to be_empty
      expect(TestJob2.jobs.size).to eq 1
      expect(TestJob3.jobs.size).to eq 1
    end

    it 'must not start subsequent jobs if all not done' do
      class TestWorkflow < Sidekiq::Workflow
        def configure
          job1 = job TestJob1
          job2 = job TestJob2
          job TestJob3, after: [job1, job2]
        end
      end

      TestWorkflow.start!
      expect(TestJob1.jobs.size).to eq 1
      expect(TestJob2.jobs.size).to eq 1
      expect(TestJob3.jobs).to be_empty

      TestJob1.perform_one
      expect(TestJob1.jobs).to be_empty
      expect(TestJob2.jobs.size).to eq 1
      expect(TestJob3.jobs).to be_empty

      TestJob2.perform_one
      expect(TestJob1.jobs).to be_empty
      expect(TestJob2.jobs).to be_empty
      expect(TestJob3.jobs.size).to eq 1
    end
  end

  describe '#status' do
    it 'must return correct status' do
      job1     = Sidekiq::Workflow::Job.new 'workflow', 'job_1', 'class'
      job2     = Sidekiq::Workflow::Job.new 'workflow', 'job_2', 'class'
      workflow = Sidekiq::Workflow.new 'class', 'workflow_1',
                                       { job1.id => job1, job2.id => job2 }
      expect(workflow.status).to eq :pending
      job1.started_at = Time.now
      expect(workflow.status).to eq :started
      job1.error_at = Time.now
      expect(workflow.status).to eq :error
      job1.finished_at = Time.now
      expect(workflow.status).to eq :error
      job2.finished_at = Time.now
      expect(workflow.status).to eq :finished
      job1.failed_at = Time.now
      expect(workflow.status).to eq :failed
    end
  end
end
