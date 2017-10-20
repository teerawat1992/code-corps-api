defmodule CodeCorps.GitHub.Sync.PullRequest do
  alias CodeCorps.{
    GitHub.Sync.Utils.RepoFinder,
    Repo,
    Task
  }
  alias CodeCorps.GitHub.Sync.PullRequest.GithubPullRequest, as: GithubPullRequestSyncer
  alias CodeCorps.GitHub.Sync.PullRequest.Task, as: PullRequestTaskSyncer
  alias CodeCorps.GitHub.Sync.User.RecordLinker, as: UserRecordLinker
  alias Ecto.Multi

  @type outcome :: {:ok, list(Task.t)}
                 | {:error, :repo_not_found}
                 | {:error, :validating_user}
                 | {:error, :multiple_github_users_match}
                 | {:error, :validating_tasks}
                 | {:error, :unexpected_transaction_outcome}

  @doc ~S"""
  Syncs a GitHub pull request API payload with our data.

  The process is as follows:

  - match payload with affected `CodeCorps.GithubRepo` record using
    `CodeCorps.GitHub.Sync.Utils.RepoFinder`
  - match with `CodeCorps.User` using
    `CodeCorps.GitHub.Event.PullRequest.UserLinker`
  - for each `CodeCorps.ProjectGithubRepo` belonging to matched repo:
    - create or update `CodeCorps.Task` for the `CodeCorps.Project`

  If the sync succeeds, it will return an `:ok` tuple with a list of created or
  updated tasks.

  If the sync fails, it will return an `:error` tuple, where the second element
  is the atom indicating a reason.
  """
  @spec sync(map) :: outcome
  def sync(payload) do
    payload
    |> operational_multi()
    |> Repo.transaction
    |> marshall_result()
  end

  @spec operational_multi(map) :: Multi.t
  defp operational_multi(payload) do
    Multi.new
    Multi.new
    |> Multi.run(:repo, fn _ -> RepoFinder.find_repo(payload) end)
    |> Multi.run(:pull_request, fn %{repo: github_repo} -> link_pull_request(github_repo, payload) end)
    |> Multi.run(:user, fn %{pull_request: github_pull_request} -> UserRecordLinker.link_to(github_pull_request, payload) end)
    |> Multi.run(:tasks, fn %{pull_request: github_pull_request, user: user} -> github_pull_request |> PullRequestTaskSyncer.sync_all(user, payload) end)
  end

  @spec link_pull_request(GithubRepo.t, map) :: {:ok, GithubIssue.t} | {:error, Ecto.Changeset.t}
  defp link_pull_request(github_repo, %{"pull_request" => attrs}) do
    GithubPullRequestSyncer.create_or_update_pull_request(github_repo, attrs)
  end

  @spec marshall_result(tuple) :: tuple
  defp marshall_result({:ok, %{tasks: tasks}}), do: {:ok, tasks}
  defp marshall_result({:error, :repo, :unmatched_project, _steps}), do: {:ok, []}
  defp marshall_result({:error, :repo, :unmatched_repository, _steps}), do: {:error, :repo_not_found}
  defp marshall_result({:error, :user, %Ecto.Changeset{}, _steps}), do: {:error, :validating_user}
  defp marshall_result({:error, :user, :multiple_users, _steps}), do: {:error, :multiple_github_users_match}
  defp marshall_result({:error, :tasks, {_tasks, _errors}, _steps}), do: {:error, :validating_tasks}
  defp marshall_result({:error, _errored_step, _error_response, _steps}), do: {:error, :unexpected_transaction_outcome}
end
