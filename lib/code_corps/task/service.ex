defmodule CodeCorps.Task.Service do
  @moduledoc """
  Handles special CRUD operations for `CodeCorps.Task`.
  """

  alias CodeCorps.{GitHub, GithubIssue, Repo, Task}
  alias GitHub.Sync.Issue.GithubIssue, as: IssueGithubIssueSyncer
  alias Ecto.{Changeset, Multi}

  require Logger

  @doc ~S"""
  Performs all actions involved in creating a task on a project
  """
  @spec create(map) :: {:ok, Task.t} | {:error, Changeset.t} | {:error, :github}
  def create(%{} = attributes) do
    Multi.new
    |> Multi.insert(:task, %Task{} |> Task.create_changeset(attributes))
    |> Multi.run(:github, (fn %{task: %Task{} = task} -> task |> create_on_github() end))
    |> Repo.transaction
    |> marshall_result()
  end

  @spec update(Task.t, map) :: {:ok, Task.t} | {:error, Changeset.t} | {:error, :github}
  def update(%Task{github_issue_id: nil} = task, %{} = attributes) do
    Multi.new
    |> Multi.update(:task, task |> Task.update_changeset(attributes))
    |> Repo.transaction
    |> marshall_result()
  end
  def update(%Task{} = task, %{} = attributes) do
    Multi.new
    |> Multi.update(:task, task |> Task.update_changeset(attributes))
    |> Multi.run(:github, (fn %{task: %Task{} = task} -> task |> update_on_github() end))
    |> Repo.transaction
    |> marshall_result()
  end

  @spec marshall_result(tuple) :: {:ok, Task.t} | {:error, Changeset.t} | {:error, :github}
  defp marshall_result({:ok, %{github: %Task{} = task}}), do: {:ok, task}
  defp marshall_result({:ok, %{task: %Task{} = task}}), do: {:ok, task}
  defp marshall_result({:error, :task, %Changeset{} = changeset, _steps}), do: {:error, changeset}
  defp marshall_result({:error, :github, result, _steps}) do
    Logger.info "An error occurred when creating/updating the task with the GitHub API"
    Logger.info "#{inspect result}"
    {:error, :github}
  end

  # :user, :github_issue and :github_repo are required for connecting to github
  # :project and :organization are required in order to add a header to the
  # github issue body when the user themselves are not connected to github, but
  # the task is
  #
  # Right now, all of these preloads are loaded at once. If there are
  # performance issues, we can split them up according the the information
  # provided here.
  @preloads [:github_issue, [github_repo: :github_app_installation], :user, [project: :organization]]

  @spec create_on_github(Task.t) :: {:ok, Task.t} :: {:error, GitHub.api_error_struct}
  defp create_on_github(%Task{github_repo_id: nil} = task) do
    # Don't create: no GitHub repo was selected
    {:ok, task}
  end
  defp create_on_github(%Task{github_repo: _} = task) do
    with %Task{github_repo: github_repo} = task <- task |> Repo.preload(@preloads),
         {:ok, payload} <- GitHub.API.Issue.create(task),
         {:ok, %GithubIssue{} = github_issue } <- IssueGithubIssueSyncer.create_or_update_issue(github_repo, payload) do
      task |> link_with_github_changeset(github_issue) |> Repo.update
    else
      {:error, error} -> {:error, error}
    end
  end

  @spec link_with_github_changeset(Task.t, GithubIssue.t) :: Changeset.t
  defp link_with_github_changeset(%Task{} = task, %GithubIssue{} = github_issue) do
    task |> Changeset.change(%{github_issue: github_issue})
  end

  @spec update_on_github(Task.t) :: {:ok, Task.t} :: {:error, GitHub.api_error_struct}
  defp update_on_github(%Task{github_repo_id: nil} = task), do: {:ok, task}
  defp update_on_github(%Task{github_repo_id: _} = task) do
    with %Task{github_repo: github_repo} = task <- task |> Repo.preload(@preloads),
         {:ok, payload} <- GitHub.API.Issue.update(task),
         {:ok, %GithubIssue{} } <- IssueGithubIssueSyncer.create_or_update_issue(github_repo, payload) do
      {:ok, task}
    else
      {:error, github_error} -> {:error, github_error}
    end
  end
end
