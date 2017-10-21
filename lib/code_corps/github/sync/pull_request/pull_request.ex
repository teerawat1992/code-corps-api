defmodule CodeCorps.GitHub.Sync.PullRequest do
  alias CodeCorps.{
    Task
  }
  alias CodeCorps.GitHub.Sync.PullRequest.GithubPullRequest, as: GithubPullRequestSyncer
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
  @spec sync(map, map) :: outcome
  def sync(changes, payload) do
    operational_multi(changes, payload)
  end

  @spec operational_multi(map, map) :: Multi.t
  defp operational_multi(%{repo: github_repo}, payload) do
    Multi.new
    |> Multi.run(:pull_request, fn _ -> link_pull_request(github_repo, payload) end)
    |> Multi.run(:user, fn %{pull_request: github_pull_request} -> UserRecordLinker.link_to(github_pull_request, payload) end)
  end

  @spec link_pull_request(GithubRepo.t, map) :: {:ok, GithubIssue.t} | {:error, Ecto.Changeset.t}
  defp link_pull_request(github_repo, %{"pull_request" => attrs}) do
    GithubPullRequestSyncer.create_or_update_pull_request(github_repo, attrs)
  end
end
