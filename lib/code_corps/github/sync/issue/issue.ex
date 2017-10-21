defmodule CodeCorps.GitHub.Sync.Issue do
  alias CodeCorps.GitHub
  alias GitHub.Sync.Issue.GithubIssue, as: IssueGithubIssueSyncer
  alias GitHub.Sync.Issue.Task, as: IssueTaskSyncer
  alias GitHub.Sync.User.RecordLinker, as: UserRecordLinker
  alias Ecto.Multi

  @doc ~S"""
  Syncs a GitHub issue API payload with our data.

  The process is as follows:

  - match with `CodeCorps.User` using `CodeCorps.GitHub.Sync.User.RecordLinker`
  - for each `CodeCorps.ProjectGithubRepo` belonging to the matched repo:
    - create or update `CodeCorps.Task` for the `CodeCorps.Project`

  If the sync succeeds, it will return an `:ok` tuple with a list of created or
  updated tasks.

  If the sync fails, it will return an `:error` tuple, where the second element
  is the atom indicating a reason.
  """
  @spec sync((map -> Multi.t), map) :: Multi.t
  def sync(%{fetch_issue: issue} = changes, _payload) do
    operational_multi(changes, issue)
  end
  def sync(changes, payload) do
    operational_multi(changes, payload)
  end

  @spec operational_multi(map, map) :: Multi.t
  defp operational_multi(%{repo: github_repo}, payload) do
    Multi.new
    |> Multi.run(:github_issue, fn _ -> link_issue(github_repo, payload) end)
    |> Multi.run(:issue_user, fn %{github_issue: github_issue} -> UserRecordLinker.link_to(github_issue, payload) end)
    |> Multi.run(:tasks, fn %{github_issue: github_issue, issue_user: user} -> github_issue |> IssueTaskSyncer.sync_all(user, payload) end)
  end

  @spec link_issue(GithubRepo.t, map) :: {:ok, GithubIssue.t} | {:error, Ecto.Changeset.t}
  defp link_issue(github_repo, attrs) do
    IssueGithubIssueSyncer.create_or_update_issue(github_repo, attrs)
  end
end
