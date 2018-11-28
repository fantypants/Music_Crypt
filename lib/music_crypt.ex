defmodule MusicCrypt do
  use Application

  def start(_type, _args) do
    print_ascii_header()
    Elixium.Store.Ledger.initialize()

    # TODO: Make genesis block mined rather than hard-coded
    if !Elixium.Store.Ledger.empty?() do
      Elixium.Store.Ledger.hydrate()
    end
    Elixium.Store.Utxo.initialize()
    Elixium.Pool.Orphan.initialize()
    MusicCrypt.Supervisor.start_link()
  end


  def encrypt_file(path) do
    path = "./" <> path
    generated_key = "test"
    :os.cmd('gpg -c --passphrase \"#{generated_key}\" test.txt') |> IO.inspect
  end
end
