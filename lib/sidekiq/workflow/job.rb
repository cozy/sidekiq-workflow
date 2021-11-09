class Sidekiq::Workflow::Job
  attr_reader :workflow, :id, :klass, :args, :errors
  attr_accessor :before, :after,
                :enqueued_at, :started_at, :finished_at, :error_at, :failed_at

  def initialize(workflow, id, klass, *args, before: [], after: [],
                 enqueued_at: nil, started_at: nil,
                 finished_at: nil, error_at: nil, failed_at: nil,
                 errors: [])
    @workflow    = workflow
    @id          = id
    @klass       = klass
    @before      = before
    @after       = after
    @args        = args
    @enqueued_at = enqueued_at
    @started_at  = started_at
    @finished_at = finished_at
    @error_at    = error_at
    @failed_at   = failed_at
    @errors      = errors
  end

  %i[enqueued started finished error failed].each do |state|
    define_method("#{state}?") { !self.send("#{state}_at").nil? }
  end

  def pending?
    self.enqueued? && !(self.finished? || self.failed?)
  end

  def enqueueable?
    self.enqueued_at.nil? && self.after.all? { |j| Sidekiq::Workflow::Client.instance.load_job(j).finished? }
  end

  TERMINAL_STATES = %i[finished failed].freeze

  def status
    return :failed if self.failed?
    return :finished if self.finished?
    return :error if self.error?
    return :started if self.started?
    return :enqueued if self.enqueued?
    :pending
  end

  %i[before after].each do |dep|
    define_method("have_#{dep}?") { !self.instance_variable_get(:"@#{dep}").empty? }
    define_method("include_#{dep}?") { |id| self.instance_variable_get(:"@#{dep}").include? id }
  end

  def initial_job?
    !self.have_after?
  end

  def self.create(workflow, klass, *args)
    self.new workflow.id, SecureRandom.uuid, klass, *args
  end

  def error!(exception)
    now = Time.now
    self.errors << { date: now, error: exception.to_s }
    self.error_at = now
  end

  def fail!
    self.failed_at = Time.now
  end

  def restart!
    self.failed_at = nil
    self.persist!
    self.perform
  end

  def persist!
    Sidekiq::Workflow::Client.instance.persist_job self
  end

  def self.find(id)
    Sidekiq::Workflow::Client.instance.load_job id
  end

  def perform
    Object.const_get(@klass).perform_async self.id, *@args
  end
end
