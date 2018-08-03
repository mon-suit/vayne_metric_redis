defmodule Vayne.Metric.RedisSentinel do
  @behaviour Vayne.Task.Metric

  @moduledoc """
  Get Redis metrics
  """

  @doc """
  Params below:

  * `host`: Redis sentinel host. Required.
  * `port`: Redis sentinel port. Not required, default 27017.
  * `password`: password. Not required.

  """

  def init(params) do
    if Map.has_key?(params, "host") do
      params = Enum.reduce(~w(host port password), [], fn (k, acc) ->
        if params[k] do
          Keyword.put(acc, String.to_atom(k), params[k])
        else
          acc
        end
      end)
      case Redix.start_link(params) do
        {:ok, conn} -> {:ok, conn}
        {:error, error} -> {:error, error}
      end
    else
      {:error, "host is required"}
    end
  end

  def clean(conn) do
    Process.exit(conn, :exit)
    :ok
  end

  def run(conn, log_func) do

    Process.flag(:trap_exit, true)

    metric = try do
      case Redix.command(conn, ~w(INFO)) do
        {:error, reason} -> 
          log_func.(reason)
          %{"redis_sentinel.alive" => 0}
        {:ok, raw} ->
          hash = normalize(raw) 
          %{"redis_sentinel.alive" => 1} |> get_number_value(hash)
      end
    rescue
      err -> 
        log_func.(err)
        %{"redis_sentinel.alive" => 0}
    catch
      :exit, err ->
        log_func.(err)
        %{"redis_sentinel.alive" => 0}
    end

    {:ok, metric}
  end

  def get_number_value(acc, hash) do
    hash
    |> Map.to_list
    |> Enum.reduce(acc, fn
      ({k, v}, acc) when is_number(v) -> Map.put(acc, k, v)
      (_, acc) -> acc
    end)
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

