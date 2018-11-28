defmodule MusicCrypt.Supervisor do
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_args) do
    port = Application.get_env(:music_crypt, :port)

    children = [
      {Elixium.Node.Supervisor, [:"Elixir.MusicCrypt.PeerRouter", port]},
      MusicCrypt.PeerRouter.Supervisor
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
