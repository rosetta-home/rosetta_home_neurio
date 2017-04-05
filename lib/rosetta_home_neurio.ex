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
    mac = device |> Map.get("meter_mac_id")
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

  @url System.get_env("NEURIO_URL")

  def register_callbacks do
    Logger.info "Starting Neurio"
    case @url do
      "" -> nil
      nil -> nil
      address -> Process.send_after(self(), {:get, address}, 1000)
    end
    {:ok, []}
  end

  def handle_info({:get, address}, state) do
    Process.send_after(self(), {:get, address}, 1000)
    state =
      case address |> Neurio.get do
        {:ok, %HTTPoison.Response{} = res} ->
          res
          |> Map.get(:body, %{})
          |> handle_device(SmartMeter.Neurio, state)
        {:error, %HTTPoison.Error{} = err} ->
          Logger.debug "Neurio Client Error: #{err.reason}"
          state
      end
    {:noreply, state}
  end

  def handle_info(_device, state) do
    {:noreply, state}
  end

end
