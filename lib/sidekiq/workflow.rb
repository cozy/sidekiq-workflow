require 'sidekiq'

class Sidekiq::Workflow
  attr_reader :id
  attr_reader :jobs, :depends

  def self.configure(config)
    Client.instance.configure config
  end

  def initialize(id, jobs = {})
    @id      = id
    @jobs    = jobs
    @depends = []
  end

  def start!
    initial_jobs = self.initial_jobs
    initial_jobs.each { |_, j| j.perform }
  end

  def persist!
    Client.instance.persist_workflow self
  end

  def self.start!(...)
    workflow = self.create
    workflow.configure(...)

    depends = workflow.depends
    jobs    = workflow.jobs
    jobs.each do |id, job|
      job.before = depends.select { |b, _| b == id }.collect &:last
      job.after  = depends.select { |_, a| a == id }.collect &:first
    end

    workflow.persist!
    workflow.start!
    workflow
  end

  def self.find(id)
    Client.instance.load_workflow id
  end

  def status
    return :failed if @jobs.any? { |_, j| j.failed? }
    return :error if @jobs.any? { |_, j| j.error? }
    return :finished if @jobs.all? { |_, j| j.finished? }
    return :pending
  end

  private

  def self.create
    self.new SecureRandom.uuid
  end

  def job(*args, before: nil, after: nil)
    job       = Job.create self, *args, {}
    id        = job.id
    @jobs[id] = job

    Array(before).each { |b| @depends << [id, b] } if before
    Array(after).each { |b| @depends << [b, id] } if after

    id
  end

  def initial_jobs
    @jobs.select { |_, j| j.initial_job? }.to_h
  end
end

require 'sidekiq/workflow/client'
require 'sidekiq/workflow/worker'
require 'sidekiq/workflow/job'
