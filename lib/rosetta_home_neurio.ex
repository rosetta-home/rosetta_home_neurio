defmodule Cicada.DeviceManager.Device.SmartMeter.Neurio do
  use Cicada.DeviceManager.DeviceHistogram
  require Logger
  alias Cicada.{DeviceManager}
  @behaviour DeviceManager.Behaviour.SmartMeter

  def start_link(id, device) do
    GenServer.start_link(__MODULE__, {id, device}, name: id)
  end

  def demand(pid) do
    GenServer.call(pid, :demand)
  end

  def produced(pid) do
    GenServer.call(pid, :produced)
  end

  def consumed(pid) do
    GenServer.call(pid, :consumed)
  end

  def price(pid) do
    GenServer.call(pid, :consumed)
  end

  def device(pid) do
    GenServer.call(pid, :device)
  end

  def update_state(pid, state) do
    GenServer.call(pid, {:update, state})
  end

  def get_id(device) do
    mac = device |> Map.get(:meter_mac_id)
    :"Neurio-#{mac}"
  end

  def map_state(%Neurio.State{} = state) do
    %DeviceManager.Device.SmartMeter.State{
      connection_status: state.connection_status,
      meter_mac_id: state.meter_mac_id,
      price: state.price,
      signal: state.signal,
      meter_type: state.meter_type,
      kw_delivered: state.kw_delivered,
      kw_received: state.kw_received,
      channel: "1",
      kw: state.kw
    }
  end

  def init({id, device}) do
    {:ok, %DeviceManager.Device{
      module: Neurio,
      type: :smart_meter,
      device_pid: :"#{device.meter_mac_id}",
      interface_pid: id,
      name: "Neurio - #{device.meter_mac_id}",
      state: device |> map_state
    }}
  end

  def handle_call({:update, state}, _from, device) do
    state = state |> map_state
    {:reply, state, %DeviceManager.Device{device | state: state}}
  end

  def handle_call(:device, _from, device) do
    {:reply, device, device}
  end

  def handle_call(:demand, _from, device) do
    {:reply, device.kw_received, device}
  end

  def handle_call(:produced, _from, device) do
    {:reply, device.kw_received, device}
  end

  def handle_call(:consumed, _from, device) do
    {:reply, device.kw_delivered, device}
  end

  def handle_call(:price, _from, device) do
    {:reply, device.price, device}
  end

end

defmodule Cicada.DeviceManager.Discovery.SmartMeter.Neurio do
  use Cicada.DeviceManager.Discovery
  require Logger
  alias Cicada.DeviceManager.Device.SmartMeter
  alias Cicada.NetworkManager
  alias Cicada.NetworkManager.State, as: NM

  @url System.get_env("NEURIO_URL")

  def register_callbacks do
    Logger.info "Starting Neurio"
    NetworkManager.register
    case NetworkManager.up do
      true -> Process.send_after(self(), {:get, address}, 1000)
      false -> nil
    end
    SmartMeter.Neurio
  end

  def handle_info(:fake_data, state) do
    state =
      %Neurio.State{
        connection_status: "connected",
        meter_mac_id: "0xFAK#3",
        price: 0.04,
        signal: 100,
        meter_type: :electric,
        kw_delivered: 1440.00,
        kw_received: 0.00,
        channel: "1",
        kw: :rand.uniform()
      } |> handle_device(state)
    Process.send_after(self(), :fake_data, 1100)
    {:noreply, state}
  end

  def handle_info(%NM{bound: true}, state) do
    case @url do
      "" -> nil
      nil -> nil
      address -> Process.send_after(self(), {:get, address}, 1000)
    end
    {:noreply, state}
  end

  def handle_info(%NM{}, state), do: {:noreply, state}

  def handle_info({:get, address}, state) do
    state =
      case address |> Neurio.get([], [recv_timeout: 3100, timeout: 3100]) do
        {:ok, %HTTPoison.Response{} = res} ->
          res
          |> Map.get(:body, %{})
          |> handle_device(state)
        {:error, %HTTPoison.Error{} = err} ->
          Logger.info "Neurio Client Error: #{err.reason}"
          state
      end
    Process.send_after(self(), {:get, address}, 1300)
    {:noreply, state}
  end

  def handle_info(_device, state) do
    {:noreply, state}
  end

end
