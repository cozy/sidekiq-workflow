require 'sidekiq'

class Sidekiq::Workflow
  attr_reader :klass, :id, :jobs, :depends

  def self.configure(config)
    Client.instance.configure config
  end

  def initialize(klass, id, jobs = {})
    @klass   = klass
    @id      = id
    @jobs    = jobs
    @depends = []
  end

  def start!
    self.initial_jobs.each { |_, j| j.perform }
  end

  def persist!
    Client.instance.persist_workflow self
  end

  def reload!
    @jobs = Client.instance.load_jobs @jobs.keys
  end

  def continue!
    @jobs.select { |_, j| j.failed? }
         .each { |_, j| j.restart! }.to_h
  end

  def self.create!(...)
    workflow = self.create(...)

    depends = workflow.depends
    jobs    = workflow.jobs
    jobs.each do |id, job|
      job.before = depends.select { |b, _| b == id }.collect &:last
      job.after  = depends.select { |_, a| a == id }.collect &:first
    end

    workflow.persist!
    workflow
  end

  def self.start!(...)
    workflow = self.create!(...)
    workflow.start!
    workflow
  end

  def self.[](id)
    Client.instance.load_workflow id
  end

  def self.find(id)
    workflow = self[id]
    raise "Workflow #{id} not found" unless workflow
    workflow
  end

  TERMINAL_STATES = %i[failed finished].freeze

  def status
    return :failed if @jobs.any? { |_, j| j.failed? }
    return :finished if @jobs.all? { |_, j| j.finished? }
    return :error if @jobs.any? { |_, j| j.error? }
    return :started if @jobs.any? { |_, j| j.started? }
    return :pending
  end

  def [](klass)
    klass = klass.name
    @jobs.select { |_, j| j.klass == klass }.to_h
  end

  def wait(delay = 1, exit_at_first_error: false, debug: false)
    stop_states = TERMINAL_STATES.dup
    stop_states << :error if exit_at_first_error
    while true
      status = self.status
      ap status if debug
      break if stop_states.include? status
      sleep delay
      self.reload!
    end
    self
  end

  private

  def self.create(...)
    workflow = self.new self.name, SecureRandom.uuid
    workflow.configure(...)
    workflow
  end

  def job(klass, *args, before: nil, after: nil)
    job       = Job.create self, klass.name, *args
    id        = job.id
    @jobs[id] = job

    Array(before).each { |b| @depends << [id, b] } if before
    Array(after).each { |b| @depends << [b, id] } if after

    id
  end

  def initial_jobs
    @jobs.select { |_, j| j.initial_job? }.to_h
  end

  def table
    Sidekiq::Workflow::Overview.new(self).to_s
  end
end

require 'sidekiq/workflow/client'
require 'sidekiq/workflow/worker'
require 'sidekiq/workflow/job'
require 'sidekiq/workflow/overview'
