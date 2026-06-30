defmodule Libdev.XConf do
  @moduledoc false

  # sobelow_skip ["Traversal.FileModule"]
  def read_config_file(path) do
    case File.read(path) do
      {:ok, content} -> eval_config(content, path)
      {:error, :enoent} -> {:ok, %{}}
      {:error, _} = err -> err
    end
  end

  def eval_config(elixir_code, path) do
    {result, _binding} = Code.eval_string(elixir_code, [], file: path)
    {:ok, result}
  rescue
    e in [SyntaxError, TokenMissingError, MismatchedDelimiterError] ->
      {:error, format_syntax_error(elixir_code, e)}

    e ->
      {:error, "could not load #{path}: #{Exception.message(e)}"}
  end

  defp format_syntax_error(code, error) do
    line_no = error.line

    window =
      code
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.filter(fn {_line, n} -> n >= line_no - 2 and n <= line_no + 2 end)
      |> Enum.map_join("\n", fn {line, n} ->
        marker =
          if n == line_no do
            ">"
          else
            " "
          end

        "#{marker} #{String.pad_leading(Integer.to_string(n), 4)} | #{line}"
      end)

    "syntax error in #{error.file} on line #{line_no}: #{error.description}\n\n#{window}"
  end

  def fetch(xconf, path, caster, default) do
    case resolve(xconf, path) do
      {:ok, value} ->
        case cast(value, caster) do
          {:ok, casted} -> {:ok, casted}
          {:error, reason} -> {:error, errmsg(path, reason)}
        end

      :error ->
        {:ok, default}
    end
  end

  def fetch_multiple(xconf, vars) do
    fetch_multiple(xconf, vars, %{})
  end

  defp fetch_multiple(xconf, [{key, {path, caster, default}} | vars], acc) do
    case fetch(xconf, path, caster, default) do
      {:ok, value} -> fetch_multiple(xconf, vars, Map.put(acc, key, value))
      {:error, _} = err -> err
    end
  end

  defp fetch_multiple(_xconf, [], acc) do
    {:ok, acc}
  end

  def fetch!(xconf, path, caster, default) do
    case fetch(xconf, path, caster, default) do
      {:ok, value} -> value
      {:error, errmsg} when is_binary(errmsg) -> raise RuntimeError, message: errmsg
    end
  end

  defp resolve(data, [h | t]) do
    with {:ok, sub} <- resolve(data, h) do
      resolve(sub, t)
    end
  end

  defp resolve(data, []) do
    {:ok, data}
  end

  defp resolve(data, k) when is_map(data) and is_atom(k) do
    Map.fetch(data, k)
  end

  defp resolve(data, k) when is_list(data) and is_atom(k) do
    Keyword.fetch(data, k)
  end

  defp resolve(data, k) do
    raise "Invalid .libdev.exs configuration, could not read key #{inspect(k)} from #{inspect(data)}"
  end

  defp cast(value, :integer) when is_integer(value) do
    {:ok, value}
  end

  defp cast(_, :integer) do
    {:error, "not an integer"}
  end

  defp cast(value, :boolean) when is_boolean(value) do
    {:ok, value}
  end

  defp cast(_, :boolean) do
    {:error, "not a boolean"}
  end

  defp cast(value, :atom) when is_atom(value) do
    {:ok, value}
  end

  defp cast(_, :atom) do
    {:error, "not an atom"}
  end

  defp cast(value, :string) when is_binary(value) do
    {:ok, value}
  end

  defp cast(_, :string) do
    {:error, "not a string"}
  end

  defp cast(value, :list) when is_list(value) do
    {:ok, value}
  end

  defp cast(_, :list) do
    {:error, "not a list"}
  end

  defp cast(value, caster) when is_function(caster, 1) do
    case caster.(value) do
      {:ok, _} = fine ->
        fine

      {:error, errmsg} = err when is_binary(errmsg) ->
        err

      other ->
        raise "invalid XConf caster return value, expected {:ok, value} | {:error, String.t()}, got: #{inspect(other)}"
    end
  end

  defp cast(list, {:list, subtype}) when is_list(list) do
    cast_list =
      Enum.map(list, fn item ->
        case cast(item, subtype) do
          {:ok, sub} -> sub
          {:error, e} -> throw({:invalid_sub, item, e})
        end
      end)

    {:ok, cast_list}
  catch
    {:invalid_sub, item, errmsg} when is_function(subtype) ->
      {:error, "not a list of valid items, item #{inspect(item)} is invalid: #{errmsg}"}
  end

  defp cast(_, {:list, _}) do
    {:error, "not a list"}
  end

  defp cast(list, {:keyword, subtype}) when is_list(list) do
    cast_list =
      Enum.map(list, fn
        {key, value} when is_atom(key) ->
          case cast(value, subtype) do
            {:ok, sub} -> {key, sub}
            {:error, e} -> throw({:invalid_sub, key, e})
          end

        other ->
          throw({:not_keyword, other})
      end)

    {:ok, cast_list}
  catch
    {:invalid_sub, key, errmsg} ->
      {:error,
       "not a keyword list of valid items, value at #{inspect(key)} is invalid: #{errmsg}"}

    {:not_keyword, other} ->
      {:error, "not a keyword list, got entry #{inspect(other)}"}
  end

  defp cast(_, {:keyword, _}) do
    {:error, "not a keyword list"}
  end

  defp errmsg(path, reason) do
    "invalid value in .libdev.exs configugration at #{format_path(path)}: #{reason}"
  end

  defp format_path(path) do
    inspect(path)
  end
end
