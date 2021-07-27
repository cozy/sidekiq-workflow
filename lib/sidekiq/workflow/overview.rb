require 'terminal-table'
require 'colorize'

class Sidekiq::Workflow::Overview
  def initialize(workflow)
    @workflow = workflow
  end

  STATUS = {
    pending:  { color: :cyan, label: 'Pending', symbol: '💤' },
    enqueued: { color: :blue, label: 'Enqueued', symbol: '🕓' },
    running:  { color: :yellow, label: 'Running', symbol: '⚙️' },
    error:    { color: :magenta, label: 'Retrying', symbol: '🔁' },
    failed:   { color: :red, label: 'Failed', symbol: '❌' },
    finished: { color: :green, label: 'Succeeded', symbol: '✅' }
  }.freeze

  def status(status)
    color, label, symbol = STATUS.fetch(status.to_sym).values_at :color, :label, :symbol
    "#{symbol} #{label.colorize(color)}"
  end

  def ascii
    errors = {}
    jobs   = Terminal::Table.new do |t|
      @workflow.jobs.each do |_, job|
        t << [job.id, job.klass, self.status(job.status)]
        e           = job.errors
        errors[job] = e unless e.empty?
      end
    end
    errors = errors.empty? ? nil : Terminal::Table.new do |t|
      errors.each do |job, es|
        t << ["#{job.klass} #{job.id}", es]
      end
    end
    Terminal::Table.new do |t|
      t << ['ID', @workflow.id]
      t << ['Name', @workflow.klass]
      t << ['Status', self.status(@workflow.status)]
      t << ['Jobs', jobs]
      t << ['Errors', errors] if errors
    end
  end
end
