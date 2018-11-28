defmodule MusicCrypt.PeerRouter do
  use GenServer
  require Logger
  require IEx
  alias Elixium.Node.Supervisor, as: Peer
  alias Miner.LedgerManager
  alias Miner.BlockCalculator
  alias Elixium.Store.Ledger
  alias Elixium.Pool.Orphan
  alias Elixium.Block
  alias Elixium.Transaction
  alias Elixium.Validator

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_args) do
    {:ok, []}
  end

  @doc """
    Sends a newly mined block to the connection handlers so that it can be
    relayed across the network.
  """
  @spec distribute_block(Elixium.Block) :: none
  def distribute_block(block) do
    Enum.each(Peer.connected_handlers(), &send(&1, {"BLOCK", block}))
  end

  # Handles recieved blocks
  def handle_info({block = %{type: "BLOCK"}, caller}, state) do
    block = Block.sanitize(block)

    case LedgerManager.handle_new_block(block) do
      :ok ->
        # We've received a valid block. We need to stop mining the block we're
        # currently working on and start mining the new one. We also need to gossip
        # this block to all the nodes we know of.
        Logger.info("Received valid block (#{block.hash}) at index #{:binary.decode_unsigned(block.index)}.")
        Peer.gossip("BLOCK", block)
        Logger.info("Gossipped block #{block.hash} to peers.")

      :gossip ->
        # For one reason or another, we want to gossip this block without
        # restarting our current block calculation. (Perhaps this is a fork block)
        Peer.gossip("BLOCK", block)
        Logger.info("Gossipped block #{block.hash} to peers.")

      {:missing_blocks, fork_chain} ->
        # We've discovered a fork, but we can't rebuild the fork chain without
        # some blocks. Let's request them from our peer.
        query_block(:binary.decode_unsigned(hd(fork_chain).index) - 1, caller)
      :ignore -> :ignore # We already know of this block. Ignore it
      :invalid -> Logger.info("Recieved invalid block at index #{:binary.decode_unsigned(block.index)}.")
    end

    {:noreply, state}
  end

  def handle_info({block_query_request = %{type: "BLOCK_QUERY_REQUEST"}, caller}, state) do
    send(caller, {"BLOCK_QUERY_RESPONSE", Ledger.block_at_height(block_query_request.index)})

    {:noreply, state}
  end

  def handle_info({block_query_response = %{type: "BLOCK_QUERY_RESPONSE"}, _caller}, state) do
    orphans_ahead =
      Ledger.last_block().index
      |> :binary.decode_unsigned()
      |> Kernel.+(1)
      |> Orphan.blocks_at_height()
      |> length()

    if orphans_ahead > 0 do
      # If we have an orphan with an index that is greater than our current latest
      # block, we're likely here trying to rebuild the fork chain and have requested
      # a block that we're missing.
      # TODO: FETCH BLOCKS
    end

    {:noreply, state}
  end

  # Handles a batch block query request, where another peer has asked this node to send
  # all the blocks it has since a given index.
  def handle_info({block_query_request = %{type: "BLOCK_BATCH_QUERY_REQUEST"}, caller}, state) do
    # TODO: This is a possible DOS vulnerability if an attacker requests a very
    # high amount of blocks. Need to figure out a better way to do this; maybe
    # we need to limit the maximum amount of blocks a peer is allowed to request.
    last_block = Ledger.last_block()

    blocks =
      if last_block != :err && block_query_request.starting_at <= :binary.decode_unsigned(last_block.index) do
        block_query_request.starting_at
        |> Range.new(:binary.decode_unsigned(last_block.index))
        |> Enum.map(&Ledger.block_at_height/1)
        |> Enum.filter(&(&1 != :none))
      else
        []
      end

    send(caller, {"BLOCK_BATCH_QUERY_RESPONSE", %{blocks: blocks}})

    {:noreply, state}
  end

  # Handles a batch block query response, where we've requested new blocks and are now
  # getting a response with potentially new blocks
  def handle_info({block_query_response = %{type: "BLOCK_BATCH_QUERY_RESPONSE"}, _caller}, state) do
    if length(block_query_response.blocks) > 0 do
      Logger.info("Recieved #{length(block_query_response.blocks)} new blocks from peer.")

      Enum.map(block_query_response.blocks, fn block ->
        block = Block.sanitize(block)

        if LedgerManager.handle_new_block(block) == :ok do

        end
      end)
    end

    {:noreply, state}
  end

  def handle_info({transaction = %{type: "TRANSACTION"}, _caller}, state) do
    transaction = Transaction.sanitize(transaction)

    if Validator.valid_transaction?(transaction) do
    else
      Logger.info("Received Invalid Transaction. Ignoring.")
    end

    {:noreply, state}
  end

  def handle_info({:new_outbound_connection, handler_pid}, state) do
    # Let's ask our peer for new blocks, if there
    # are any. We'll ask for all blocks starting from our current index minus
    # 120 (4 hours worth of blocks before we disconnected) just in case there
    # was a fork after we disconnected.

    Logger.info("Querying new peer for missed blocks...")

    starting_at =
      case Ledger.last_block() do
        :err -> 0
        last_block ->
          # Current index minus 120 or 1, whichever is greater.
          max(0, :binary.decode_unsigned(last_block.index) - 120)
      end

    send(handler_pid, {"BLOCK_BATCH_QUERY_REQUEST", %{starting_at: starting_at}})

    send(handler_pid, {"PEER_QUERY_REQUEST", %{}})

    {:noreply, state}
  end

  def handle_info({:new_inbound_connection, handler_pid}, state) do
    send(handler_pid, {"PEER_QUERY_REQUEST", %{}})

    {:noreply, state}
  end

  def handle_info({%{type: "PEER_QUERY_REQUEST"}, handler_pid}, state) do
    peers =
      :"Elixir.Elixium.Store.PeerOracle"
      |> GenServer.call({:load_known_peers, []})
      |> Enum.take(8)

    send(handler_pid, {"PEER_QUERY_RESPONSE", %{peers: peers}})

    {:noreply, state}
  end

  def handle_info({%{type: "PEER_QUERY_RESPONSE", peers: peers}, _caller}, state) do
    Enum.each(peers, fn peer ->
      GenServer.call(:"Elixir.Elixium.Store.PeerOracle", {:save_known_peer, [peer]})
    end)

    {:noreply, state}
  end

  def handle_info(_, state) do
    Logger.warn("Received message that isn't handled by any other case.")

    {:noreply, state}
  end

  def query_block(index, caller), do: send(caller, {"BLOCK_QUERY_REQUEST", %{index: index}})
end
