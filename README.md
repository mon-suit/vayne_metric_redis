# vayne_metric_redis
[![Build Status](https://travis-ci.org/mon-suit/vayne_metric_redis.svg?branch=master)](https://travis-ci.org/mon-suit/vayne_metric_redis)

Redis metric plugin for [vayne_core](https://github.com/mon-suit/vayne_core) monitor framework.
Checkout real monitor example to see [vayne_server](https://github.com/mon-suit/vayne_server).


## Installation

Add package to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:vayne_metric_redis, github: "mon-suit/vayne_metric_redis"}
  ]
end
```

## Usage

```elixir
#Setup params for plugin.
params = %{"host" => "127.0.0.1", "password" => "foo"}

#Init plugin.
{:ok, stat} = Vayne.Metric.Redis.init(params)

#In fact, log_func will be passed by framework to record error.
log_func = fn msg -> IO.puts msg end

#Run plugin and get returned metrics.
{:ok, metrics} = Vayne.Metric.Redis.run(stat, log_func)

#Do with metrics
IO.inspect metrics

#Clean plugin state.
:ok = Vayne.Metric.Redis.clean(stat)
```

Support params:

* `host`: Redis host.Required.
* `port`: Redis port. Not required, default 6379.
* `password`: password. Not required.
* `max_memory`: max_memory. Not required(`CONFIG GET` will failed in some cloud instance).

## Support Metrics

1. All `info` items(could be parsed to number).
2. Custom items:
  * `is_slave`: "slave" -> 1, other -> 0. (check if `failover` happen)
  * `master_link_status`: nil -> 2, "up" -> 1, other -> 0
  * `used_memory_percent`: 100 * used_memory / max_memory
  * `keys`: count of keys in db0~db15
  * `key_hits_percent`: 100 * keyspace_hits / (keyspace_hits + keyspace_misses)
  * `aof_last_bgrewrite_status` and `rdb_last_bgsave_status`: "ok" -> 1, other -> 0
  * `cluster_state`: "ok" -> 1, other -> 0. (when `cluster_enabled` == 1)
