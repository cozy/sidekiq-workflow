require 'singleton'
require 'redlock'
require 'json'

class Sidekiq::Workflow::Client
  include Singleton

  def configure(config)
    @ttl = config.delete(:ttl) { 60 * 60 * 24 * 30 }
    Sidekiq.configure_server { |c| c.redis = config }
    Sidekiq.configure_client { |c| c.redis = config }
    @redlock = Redlock::Client.new [Redis.new(config)]
  end

  def persist_workflow(workflow)
    self.redis do |redis|
      jobs = workflow.jobs
      self.persist_jobs redis, jobs
      key = "workflow::#{workflow.id}"
      redis.hset key, {
        class: workflow.class,
        jobs:  jobs.values.collect(&:id).join("\n")
      }
      redis.expire key, @ttl
    end
  end

  def load_workflow(id)
    self.redis do |redis|
      key = "workflow::#{id}"
      raise "Workflow #{id} not found" unless redis.exists? key
      workflow = redis.hgetall key
      klass    = workflow.fetch 'class'
      jobs     = workflow['jobs'].split "\n"
      jobs     = self.load_jobs redis, jobs
      Sidekiq::Workflow.new klass, id, jobs
    end
  end

  def persist_job(job)
    self.redis { |r| self._persist_job r, job }
  end

  def load_job(id)
    self.redis { |r| self._load_job r, id }
  end

  def lock(key, ttl, &block)
    @redlock.lock key, ttl, &block
  end

  def set_payload(id, name, value)
    value = case value
            when Hash, Array
              JSON.dump value
            else
              value
            end
    self.redis do |redis|
      redis.hset "workflow::payload::#{id}", name, value
    end
  end

  def get_payload(id, name, type = :string)
    self.redis do |redis|
      value = redis.hget "workflow::payload::#{id}", name
      return case type
             when :string
               value
             when :boolean
               value == 'true'
             when :integer
               value.to_i
             when :float
               value.to_f
             else
               JSON.parse value
             end
    end
  end

  private

  def redis(&block)
    # @pool.with { |r| r.multi &block }
    #@pool.with { |r| block.call r }
    Sidekiq.redis &block
  end

  def persist_jobs(redis, jobs)
    jobs.each { |_, j| self._persist_job redis, j }
  end

  def _time(time)
    return unless time
    Time.at time.to_f
  end

  def _persist_job(redis, job)
    key    = "job::#{job.id}"
    before = job.before
    after  = job.after
    errors = job.errors
    args   = job.args
    redis.hset key, {
      workflow:    job.workflow,
      class:       job.klass,
      args:        args.empty? ? nil : JSON.dump(args),
      before:      before.empty? ? nil : before.join(','),
      after:       after.empty? ? nil : after.join(','),
      enqueued_at: job.enqueued_at&.to_f,
      started_at:  job.started_at&.to_f,
      finished_at: job.finished_at&.to_f,
      error_at:    job.error_at&.to_f,
      failed_at:   job.failed_at&.to_f,
      errors:      errors.empty? ? nil : errors.join("\n")
    }.compact
    redis.expire key, @ttl
  end

  def _load_job(redis, id)
    key = "job::#{id}"
    raise "Job #{id} not found" unless redis.exists? key
    job         = redis.hgetall key
    workflow    = job.fetch 'workflow'
    klass       = job.fetch 'class'
    args        = job['args']
    args        = args ? JSON.load(args) : []
    before      = job.fetch('before', '').split(',')
    after       = job.fetch('after', '').split(',')
    errors      = job.fetch('errors', '').split "\n"
    enqueued_at = _time job['enqueued_at']
    started_at  = _time job['started_at']
    finished_at = _time job['finished_at']
    error_at    = _time job['error_at']
    failed_at   = _time job['failed_at']
    Sidekiq::Workflow::Job.new workflow, id, klass, *args,
                               before:      before, after: after,
                               enqueued_at: enqueued_at, started_at: started_at,
                               finished_at: finished_at, error_at: error_at,
                               failed_at:   failed_at, errors: errors
  end

  def load_jobs(redis, ids)
    ids.collect do |id|
      job = self._load_job redis, id
      [job.id, job]
    end.to_h
  end
end
