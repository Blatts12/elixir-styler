# Copyright 2024 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.Style.Deprecations do
  @moduledoc """
  Transformations to soft or hard deprecations introduced on newer Elixir releases
  """

  @behaviour Styler.Style

  def run({node, meta}, ctx), do: {:cont, {style(node), meta}, ctx}

  # Logger.warn => Logger.warning
  # Started to emit warning after Elixir 1.15.0
  defp style({{:., dm, [{:__aliases__, am, [:Logger]}, :warn]}, funm, args}),
    do: {{:., dm, [{:__aliases__, am, [:Logger]}, :warning]}, funm, args}

  # Path.safe_relative_to/2 => Path.safe_relative/2
  # Path.safe_relative/2 is available since v1.14
  # TODO: Remove after Elixir v1.19
  defp style({{:., dm, [{_, _, [:Path]} = mod, :safe_relative_to]}, funm, args}),
    do: {{:., dm, [mod, :safe_relative]}, funm, args}

  if Version.match?(System.version(), ">= 1.16.0-dev") do
    # File.stream!(file, options, line_or_bytes) => File.stream!(file, line_or_bytes, options)
    defp style({{:., _, [{_, _, [:File]}, :stream!]} = f, fm, [path, {:__block__, _, [modes]} = opts, lob]})
         when is_list(modes),
         do: {f, fm, [path, lob, opts]}

    # For ranges where `start > stop`, you need to explicitly include the step
    # Enum.slice(enumerable, 1..-2) => Enum.slice(enumerable, 1..-2//1)
    # String.slice("elixir", 2..-1) => String.slice("elixir", 2..-1//1)
    defp style({{:., _, [{_, _, [module]}, :slice]} = f, funm, [enumerable, {:.., _, [_, _]} = range]})
         when module in [:Enum, :String],
         do: {f, funm, [enumerable, add_step_to_decreasing_range(range)]}
  end

  # Path.safe_relative_to/2 => Path.safe_relative/2
  # Path.safe_relative/2 is available since v1.14
  # TODO: Remove after Elixir v1.19
  defp style({:|>, m, [lhs, {{:., dm, [{:__aliases__, am, [:Path]}, :safe_relative_to]}, funm, args}]}),
    do: {:|>, m, [lhs, {{:., dm, [{:__aliases__, am, [:Path]}, :safe_relative]}, funm, args}]}

  if Version.match?(System.version(), ">= 1.16.0-dev") do
    # File.stream!(file, options, line_or_bytes) => File.stream!(file, line_or_bytes, options)
    defp style({:|>, m, [lhs, {{_, _, [{_, _, [:File]}, :stream!]} = f, fm, [{:__block__, _, [modes]} = opts, lob]}]})
         when is_list(modes),
         do: {:|>, m, [lhs, {f, fm, [lob, opts]}]}

    # For ranges where `start > stop`, you need to explicitly include the step
    # Enum.slice(enumerable, 1..-2) => Enum.slice(enumerable, 1..-2//1)
    # String.slice("elixir", 2..-1) => String.slice("elixir", 2..-1//1)
    defp style({:|>, m, [lhs, {{:., _, [{_, _, [mod]}, :slice]} = f, funm, [{:.., _, [_, _]} = range]}]})
         when mod in [:Enum, :String],
         do: {:|>, m, [lhs, {f, funm, [add_step_to_decreasing_range(range)]}]}
  end

  defp style(node), do: node

  defp add_step_to_decreasing_range({:.., rm, [first, {_, lm, _} = last]} = range) do
    start = extract_value_from_range(first)
    stop = extract_value_from_range(last)

    if start > stop do
      step = {:__block__, [token: "1", line: lm[:line]], [1]}
      {:"..//", rm, [first, last, step]}
    else
      range
    end
  end

  # Extracts the positive or negative integer from the given range block
  defp extract_value_from_range({:__block__, _, [value]}), do: value
  defp extract_value_from_range({:-, _, [{:__block__, _, [value]}]}), do: -value
end