defmodule CodeCorps.GitHub.Sync do

  alias CodeCorps.{
    GitHub,
    GitHub.Sync.Utils.RepoFinder,
    Repo
  }
  alias Ecto.Multi

  @type outcome :: GitHub.Sync.Comment.outcome
                 | GitHub.Sync.Issue.outcome
                 | GitHub.Sync.PullRequest.outcome

  def issue_event(%{"issue" => _} = payload) do
    Multi.new
    |> Multi.merge(__MODULE__, :find_repo, [payload])
    |> Multi.merge(GitHub.Sync.Issue, :sync, [payload])
    |> transact()
  end

  def issue_comment_event(%{"action" => "deleted"} = payload) do
    Multi.new
    |> Multi.merge(GitHub.Sync.Comment, :delete, [payload])
    |> transact()
  end
  def issue_comment_event(%{"issue" => %{"pull_request" => %{"url" => pull_request_url}} = _, "comment" => _} = payload) do
    # Pull Request
    Multi.new
    |> Multi.merge(__MODULE__, :find_repo, [payload])
    |> Multi.merge(__MODULE__, :fetch_pull_request, [pull_request_url])
    |> Multi.merge(GitHub.Sync.Issue, :sync, [payload])
    |> Multi.merge(__MODULE__, :maybe_sync_pull_request, [payload])
    |> Multi.merge(GitHub.Sync.Comment, :sync, [payload])
    |> transact()
  end
  def issue_comment_event(%{"issue" => _, "comment" => _} = payload) do
    # Issue
    Multi.new
    |> Multi.merge(__MODULE__, :find_repo, [payload])
    |> Multi.merge(GitHub.Sync.Issue, :sync, [payload])
    |> Multi.merge(GitHub.Sync.Comment, :sync, [payload])
    |> transact()
  end

  def pull_request_event(%{"pull_request" => %{"issue_url" => issue_url}} = payload) do
    Multi.new
    |> Multi.merge(__MODULE__, :find_repo, [payload])
    |> Multi.merge(__MODULE__, :fetch_issue, [issue_url])
    |> Multi.merge(GitHub.Sync.Issue, :sync, [payload])
    |> Multi.merge(GitHub.Sync.PullRequest, :sync, [payload])
    |> transact()
  end

  def issue_api(%{"pull_request" => %{"url" => pull_request_url}} = payload) do
    # Pull Request
    Multi.new
    |> Multi.merge(__MODULE__, :find_repo, [payload])
    |> Multi.merge(__MODULE__, :fetch_pull_request, [pull_request_url])
    |> Multi.merge(GitHub.Sync.Issue, :sync, [payload])
    |> Multi.merge(GitHub.Sync.PullRequest, :sync, [payload])
    |> Multi.merge(GitHub.Sync.Comment, :sync, [payload])
    |> transact()
  end
  def issue_api(%{} = payload) do
    # Issue
    Multi.new
    |> Multi.merge(GitHub.Sync.Issue, :sync, [payload])
    |> transact()
  end

  def comment_api(%{"issue_url" => issue_url} = payload) do
    Multi.new
    |> Multi.merge(__MODULE__, :find_repo, [payload])
    |> Multi.merge(__MODULE__, :fetch_issue, [issue_url])
    |> Multi.merge(__MODULE__, :maybe_fetch_pull_request, [payload])
    |> Multi.merge(GitHub.Sync.Issue, :sync, [payload])
    |> Multi.merge(GitHub.Sync.PullRequest, :sync, [payload])
    |> Multi.merge(GitHub.Sync.Comment, :sync, [payload])
    |> transact()
  end

  def pull_request_api(%{"issue_url" => issue_url} = payload) do
    Multi.new
    |> Multi.merge(__MODULE__, :find_repo, [payload])
    |> Multi.merge(__MODULE__, :fetch_issue, [issue_url])
    |> Multi.merge(GitHub.Sync.Issue, :sync, [payload])
    |> Multi.merge(GitHub.Sync.PullRequest, :sync, [payload])
    |> transact()
  end

  def find_repo(_, payload) do
    Multi.new
    |> Multi.run(:repo, fn _ -> RepoFinder.find_repo(payload) end)
  end

  def fetch_issue(_, url) do
    Multi.new
    |> Multi.run(:fetch_issue, fn _ -> GitHub.API.Issue.from_url(url) end)
  end

  def fetch_pull_request(_, url) do
    Multi.new
    |> Multi.run(:fetch_pull_request, fn _ -> GitHub.API.PullRequest.from_url(url) end)
  end

  def maybe_fetch_pull_request(%{fetch_issue: %{"pull_request" => %{"url" => url}}} = changes, _) do
    fetch_pull_request(changes, url)
  end
  def maybe_fetch_pull_request(_, _), do: Multi.new

  def maybe_sync_pull_request(_, %{} = payload) do
    Multi.new
    |> Multi.run(:sync_pull_request, fn _ -> GitHub.Sync.PullRequest.sync(payload) end)
  end
  def maybe_sync_pull_request(_, _), do: Multi.new

  @spec transact(Multi.t) :: any
  defp transact(multi) do
    multi
    |> Repo.transaction
    |> marshall_result()
  end

  @spec marshall_result(tuple) :: tuple
  defp marshall_result({:ok, %{comments: comments}}), do: {:ok, comments}
  defp marshall_result({:ok, %{tasks: tasks}}), do: {:ok, tasks}
  defp marshall_result({:error, :repo, :unmatched_project, _steps}), do: {:ok, []}
  defp marshall_result({:error, :repo, :unmatched_repository, _steps}), do: {:error, :repo_not_found}
  defp marshall_result({:error, :github_issue, %Ecto.Changeset{}, _steps}), do: {:error, :validating_github_issue}
  defp marshall_result({:error, :github_comment, %Ecto.Changeset{}, _steps}), do: {:error, :validating_github_comment}
  defp marshall_result({:error, :comment_user, %Ecto.Changeset{}, _steps}), do: {:error, :validating_user}
  defp marshall_result({:error, :comment_user, :multiple_users, _steps}), do: {:error, :multiple_comment_users_match}
  defp marshall_result({:error, :issue_user, %Ecto.Changeset{}, _steps}), do: {:error, :validating_user}
  defp marshall_result({:error, :issue_user, :multiple_users, _steps}), do: {:error, :multiple_issue_users_match}
  defp marshall_result({:error, :comments, {_comments, _errors}, _steps}), do: {:error, :validating_comments}
  defp marshall_result({:error, :tasks, {_tasks, _errors}, _steps}), do: {:error, :validating_tasks}
  defp marshall_result({:error, _errored_step, _error_response, _steps}), do: {:error, :unexpected_transaction_outcome}
end
