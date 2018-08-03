defmodule Vayne.Metric.Redis do
  @behaviour Vayne.Task.Metric

  @moduledoc """
  Get Redis metrics
  """

  @doc """
  Params below:

  * `host`: Redis host.Required.
  * `port`: Redis port. Not required, default 6379.
  * `password`: password. Not required.
  * `max_memory`: max_memory. Not required.

  """

  def init(params) do
    if Map.has_key?(params, "host") do
      max_memory  = Map.get(params, "max_memory")
      params = Enum.reduce(~w(host port password), [], fn (k, acc) ->
        if params[k] do
          Keyword.put(acc, String.to_atom(k), params[k])
        else
          acc
        end
      end)
      case Redix.start_link(params) do
        {:ok, conn} -> {:ok, {conn, max_memory}}
        {:error, error} -> {:error, error}
      end
    else
      {:error, "host is required"}
    end
  end

  def clean({conn, _max_memory}) do
    Process.exit(conn, :exit)
    :ok
  end

  def run({conn, max_memory}, log_func) do

    Process.flag(:trap_exit, true)

    metric = try do
      case Redix.command(conn, ~w(INFO)) do
        {:error, reason} -> 
          log_func.(reason)
          %{"redis.alive" => 0}
        {:ok, raw} ->
          hash = normalize(raw) 

          %{"redis.alive" => 1}
          |> get_number_value(hash)
          |> get_memory_info(conn, hash, max_memory)
          |> get_cluster_info(conn, hash)
          |> key_hits_percent(hash)
          |> db_keys(hash)
          |> aof(hash)
          |> get_slave_role(hash)
      end
    rescue
      err -> 
        log_func.(err)
        %{"redis.alive" => 0}
    catch
      :exit, err ->
        log_func.(err)
        %{"redis.alive" => 0}
    end

    {:ok, metric}
  end

  def get_slave_role(acc, hash) do
    is_slave = if hash["role"] == "slave", do: 1, else: 0

    master_link_status = case hash["master_link_status"] do
      nil  -> 2
      "up" -> 1
      _    -> 0
    end

    acc
    |> Map.put("is_slave", is_slave)
    |> Map.put("master_link_status", master_link_status)
  end

  def aof(acc, hash) do
    acc = cond do
      hash["aof_enabled"] == 1 ->

        aof_last_bgrewrite_status = if hash["aof_last_bgrewrite_status"] == "ok", do: 1, else: 0

        acc 
        |> Map.put("aof_last_rewrite_time_sec", hash["aof_last_rewrite_time_sec"])
        |> Map.put("aof_last_bgrewrite_status", aof_last_bgrewrite_status)

      true -> acc
    end

    rdb_last_bgsave_status = if hash["rdb_last_bgsave_status"] == "ok", do: 1, else: 0

    Map.put(acc, "rdb_last_bgsave_status", rdb_last_bgsave_status)
  end

  def get_number_value(acc, hash) do
    hash
    |> Map.to_list
    |> Enum.reduce(acc, fn
      ({k, v}, acc) when is_number(v) -> Map.put(acc, k, v)
      (_, acc) -> acc
    end)
  end

  def get_memory_info(acc, conn, hash, maxmem \\ nil) do
    maxmem = if is_number(maxmem), do: maxmem, else: try_get_maxmem(conn)

    if not is_nil(maxmem) && maxmem != 0 do
      used_memory_peak_percent = hash["used_memory_peak"] / maxmem
      used_memory_percent      = hash["used_memory"] / maxmem
      acc
      |> Map.put("maxmemory", maxmem )
      |> Map.put("used_memory_peak_percent", Float.floor(used_memory_peak_percent, 3))
      |> Map.put("used_memory_percent", Float.floor(used_memory_percent, 3))
    else
      acc
    end
  end

  def try_get_maxmem(conn) do
    try do
      [_key, mem] = Redix.command!(conn, ~w(CONFIG GET maxmemory))
      String.to_integer(mem)
    rescue
      _ -> nil
    end
  end

  def get_cluster_info(acc, conn, hash) do
    if hash["cluster_enabled"] == 1 do
      try do
        c_hash = conn |> Redix.command!(~w(CLUSTER INFO)) |> normalize
        c_state = if c_hash["cluster_state"] == "ok" , do: 1, else: 0
        Map.put(acc, "cluster_state", c_state)
      rescue
        _ -> 
          acc
      end
    else
      acc
    end
  end

  def key_hits_percent(acc, hash)  do
    
    keyspace_hits   = hash["keyspace_hits"]
    keyspace_misses = hash["keyspace_misses"]

    #key_hits_percent% = keyspace_hits / keyspace_hits + keyspace_misses
    key_hits_percent = if keyspace_hits + keyspace_misses <= 0, do: 0, else: keyspace_hits / (keyspace_hits + keyspace_misses)

    Map.put(acc, "key_hits_percent", key_hits_percent)
  end

  def db_keys(acc, hash) do
    dbs  = hash |> Map.keys |> Enum.filter(fn(x) -> String.match?(x, ~r/^db/) end)

    #keys = db0-db15 
    keys = dbs |> Enum.reduce(0, fn(db, acc) -> 
        case Regex.run(~r/keys=(\d+)/, hash[db]) do
          [_, keys] -> acc + String.to_integer(keys)
          _         -> acc
        end
    end)
    Map.put(acc, "keys", keys)
  end

  defp normalize(raw) do
    raw
    |> String.split("\r\n")
    |> Enum.reduce(%{}, fn (term, acc) ->
      case Regex.run(~r/(.+):(.+)/, term) do
        [_raw, key, value] ->
          value = try_parse(value)
          Map.put(acc, key, value)
        _ ->
          acc
      end
    end)
  end

  defp try_parse(value) when is_binary(value) do
    case Integer.parse(value) do
      {v, _} -> v
      _      -> value
    end
  end
  defp try_parse(value), do: value
end

