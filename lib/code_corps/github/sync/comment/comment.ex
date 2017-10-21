defmodule CodeCorps.GitHub.Sync.Comment do
  alias CodeCorps.{
    GitHub,
    GithubComment,
    GitHub.Event.IssueComment.CommentDeleter
  }
  alias GitHub.Sync.Comment.Comment, as: CommentCommentSyncer
  alias GitHub.Sync.Comment.GithubComment, as: CommentGithubCommentSyncer
  alias GitHub.Sync.User.RecordLinker, as: UserRecordLinker
  alias Ecto.Multi

  @doc ~S"""
  Syncs a GitHub comment API payload with our data.

  The process is as follows:

  - match issue part of the payload with `CodeCorps.User` using
    `CodeCorps.GitHub.Sync.User.RecordLinker`
  - match comment part of the payload with a `CodeCorps.User` using
    `CodeCorps.GitHub.Sync.User.RecordLinker`
  - for each `CodeCorps.ProjectGithubRepo` belonging to the matched repo:
    - create or update `CodeCorps.Task` for the `CodeCorps.Project`
    - create or update `CodeCorps.Comment` for the `CodeCorps.Task`

  If the sync succeeds, it will return an `:ok` tuple with a list of created or
  updated comments.

  If the sync fails, it will return an `:error` tuple, where the second element
  is the atom indicating a reason.
  """
  @spec sync(map, map) :: Multi.t
  def sync(changes, payload) do
    operational_multi(changes, payload)
  end

  @spec delete(map, map) :: Multi.t
  def delete(_changes, %{"action" => "deleted"} = payload) do
    Multi.new
    |> Multi.run(:comments, fn _ -> CommentDeleter.delete_all(payload) end)
  end

  @spec operational_multi(map, map) :: Multi.t
  defp operational_multi(%{github_issue: github_issue, tasks: tasks}, %{"action" => action, "issue" => _, "comment" => _} = payload) when action in ~w(created edited) do
    Multi.new
    |> Multi.run(:github_comment, fn _ -> sync_comment(github_issue, payload) end)
    |> Multi.run(:comment_user, fn %{github_comment: github_comment} -> UserRecordLinker.link_to(github_comment, payload) end)
    |> Multi.run(:comments, fn %{github_comment: github_comment, comment_user: user} -> CommentCommentSyncer.sync_all(tasks, github_comment, user, payload) end)
  end
  defp operational_multi(%{}, %{}), do: Multi.new

  @spec sync_comment(GithubIssue.t, map) :: {:ok, GithubComment.t} | {:error, Ecto.Changeset.t}
  defp sync_comment(github_issue, %{"comment" => attrs}) do
    CommentGithubCommentSyncer.create_or_update_comment(github_issue, attrs)
  end
end
