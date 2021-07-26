# Sidekiq::Workflow

## Why yet another Sidekiq workflow library?

[`easymarketing/sidekiq_workflows`](https://github.com/easymarketing/sidekiq_workflows])
is only usable with [Sidekiq Pro](https://sidekiq.org/products/pro.html)

[`chaps-io/gush`](https://github.com/chaps-io/gush) move from Sidekiq to
ActiveJob on their [1.0](https://github.com/chaps-io/gush/releases/tag/v1.0.0)
and [don't support](https://github.com/chaps-io/gush/issues/18)
all advanced Sidekiq configuration like `sidekiq_options` or `sidekiq_retry_in`
because all jobs are encapsulated on a single (and shared) Sidekiq class worker.

This library try to keep all Sidekiq features available at job level,
using [`Module#prepend`](https://ruby-doc.org/core-2.7.3/Module.html#method-i-prepend)
to encapsulate own workflow behaviour around classic Sidekiq worker behaviour.

## How to use it

```ruby
require 'sidekiq/workflow'
Sidekiq::Workflow.configure url: 'redis://localhost/0'

class FetchJob
  include Sidekiq::Workflow::Worker
  sidekiq_options queue: :default, retry: 3
  sidekiq_retry_in { 10 }

  def perform(...) end
end

class SampleWorkflow < Sidekiq::Workflow
  def configure(url_to_fetch_from)
    fetch1 = job FetchJob, { url: url_to_fetch_from }
    fetch2 = job FetchJob, { some_flag: true, url: 'http://example.com' }

    persist1 = job PersistJob, after: fetch1
    persist2 = job PersistJob, after: fetch2

    index = job Index

    job Normalize, after: [persist1, persist2], before: index
  end
end

SampleWorkflow.start! 'http://example.net'
```
