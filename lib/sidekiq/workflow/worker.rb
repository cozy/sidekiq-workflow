module Sidekiq::Workflow::Worker
  module InstanceMethods
    def perform(id, *args, **kwargs)
      @job                     = Sidekiq::Workflow::Job.find id
      @workflow                = @job.workflow
      @job.started_at          ||= Time.now
      result, exception, abort = nil, nil, false
      begin
        result           = super *args, **kwargs
        @job.finished_at = Time.now
      rescue AbortException => e
        abort     = true
        exception = e.exception
        @job.fail!
      rescue Exception => e
        exception = e
      end

      @job.error! exception if exception
      @job.persist!
      self.perform_ready_jobs! unless exception

      raise exception if exception && !abort
      result
    end

    class AbortException < Exception
      def initialize(args)
        @args = args
      end

      def exception
        exception = @args.first
        return exception if exception.is_a? Exception
        clazz, *args = @args
        return clazz.new *args if clazz.is_a? Class
        RuntimeError.new *@args
      end
    end

    def abort!(*args)
      raise AbortException, args
    end

    private

    def perform_ready_jobs!
      key = "workflow::lock::#{@workflow}"
      Sidekiq::Workflow::Client.instance.lock key, 2000 do
        @job.before.each do |job|
          job = Sidekiq::Workflow::Client.instance.load_job job
          job.perform if job.enqueueable?
        end
      end
    end

    def set_payload(value, name = nil)
      name ||= @job.klass
      Sidekiq::Workflow::Client.instance.set_payload @workflow, name, value
    end

    def get_payload(name = nil, type = :string)
      name ||= @job.klass
      Sidekiq::Workflow::Client.instance.get_payload @workflow, name, type
    end
  end

  module ClassMethods
    def perform_async(id, *args, **kwargs)
      @job             = Sidekiq::Workflow::Job.find id
      @job.enqueued_at = Time.now
      @job.persist!
      super id, *args, **kwargs
    end
  end

  def self.included(base)
    base.include Sidekiq::Worker
    base.prepend InstanceMethods
    base.singleton_class.prepend ClassMethods
    base.sidekiq_retries_exhausted do |msg, _|
      id   = msg['args'].first
      @job = Sidekiq::Workflow::Job.find id
      @job.fail!
      @job.persist!
    end
  end
end
