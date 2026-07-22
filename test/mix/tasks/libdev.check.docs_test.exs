defmodule Mix.Tasks.Libdev.Check.DocsTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Libdev.Check.Docs

  # The fixture is compiled at runtime into the build directory: fixture
  # modules deliberately miss docs, so compiling them as part of the project
  # would fail the credo and docs checks that libdev runs on itself. Line
  # numbers in the assertions refer to this source.
  @fixtures_source """
  defmodule LibdevDocsFixture.FixtureBehaviour do
    @moduledoc false
    @callback run(term) :: term
  end

  defmodule LibdevDocsFixture.Bare do
    def undocumented(x), do: x

    def multi(:a), do: 1
    def multi(:b), do: 2
  end

  defmodule LibdevDocsFixture.Partial do
    @moduledoc "Partial docs fixture."

    @doc "Documented."
    def documented(x), do: x

    def missing_doc(a, b), do: {a, b}
  end

  defmodule LibdevDocsFixture.Hidden do
    @moduledoc false
    def whatever(x), do: x
  end

  defmodule LibdevDocsFixture.Callbacks do
    @moduledoc "Implements the fixture behaviour."
    @behaviour LibdevDocsFixture.FixtureBehaviour

    @impl true
    def run(x), do: x
  end
  """

  setup_all do
    dir = Path.join(Mix.Project.build_path(), "docs_check_fixtures")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)

    source_path = Path.join(dir, "doc_fixtures.ex")
    File.write!(source_path, @fixtures_source)

    # `mix test` compiles with `docs: false`, and the compiler options are
    # global, so the docs chunk must be enabled explicitly for the fixture.
    previous_docs = Code.get_compiler_option(:docs)
    Code.put_compiler_option(:docs, true)

    {:ok, modules, _warnings} =
      try do
        Kernel.ParallelCompiler.compile_to_path([source_path], dir, return_diagnostics: true)
      after
        Code.put_compiler_option(:docs, previous_docs)
      end

    # Unload the freshly compiled modules so `Code.fetch_docs/1` resolves them
    # through the on-disk beam files, as it does for regular app modules.
    Enum.each(modules, fn module ->
      :code.purge(module)
      :code.delete(module)
    end)

    true = Code.prepend_path(dir)

    {:ok, source_path: Path.relative_to_cwd(source_path)}
  end

  test "reports a missing @moduledoc with the defmodule location", %{source_path: path} do
    {[entry], counts} = Docs.scan_module(LibdevDocsFixture.Bare)

    assert entry.module == LibdevDocsFixture.Bare
    assert entry.moduledoc == :missing
    assert entry.location == "#{path}:6"

    assert counts.module_count == 1
    assert counts.module_missing == 1
    assert counts.module_ok == 0
  end

  test "reports each undocumented function with its definition location", %{source_path: path} do
    {[entry], counts} = Docs.scan_module(LibdevDocsFixture.Bare)

    assert [multi, undocumented] = entry.functions

    assert %{function: :multi, arity: 1, doc: :missing, location: "#{path}:9"} == multi

    assert %{function: :undocumented, arity: 1, doc: :missing, location: "#{path}:7"} ==
             undocumented

    assert counts.function_count == 2
    assert counts.function_missing == 2
    assert counts.function_ok == 0
  end

  test "a documented module reports only its undocumented functions", %{source_path: path} do
    {[entry], counts} = Docs.scan_module(LibdevDocsFixture.Partial)

    assert entry.moduledoc == :ok
    assert entry.location == "#{path}:13"

    assert [missing_doc] = entry.functions
    assert missing_doc.function == :missing_doc
    assert missing_doc.arity == 2
    assert missing_doc.location == "#{path}:19"

    assert counts.module_ok == 1
    assert counts.function_count == 2
    assert counts.function_ok == 1
    assert counts.function_missing == 1
  end

  test "a module with @moduledoc false is ignored entirely" do
    assert {[], counts} = Docs.scan_module(LibdevDocsFixture.Hidden)
    assert counts.module_count == 0
    assert counts.function_count == 0
  end

  test "behaviour callback implementations are skipped" do
    assert {[], counts} = Docs.scan_module(LibdevDocsFixture.Callbacks)
    assert counts.module_ok == 1
    assert counts.function_count == 0
  end
end
