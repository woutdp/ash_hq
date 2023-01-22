defmodule AshHq.Discord.Listener do
  @moduledoc """
  Does nothing for now. Eventually will support slash commands to search AshHQ from discord.
  """
  use Nostrum.Consumer

  # alias Nostrum.Api

  def start_link do
    Consumer.start_link(__MODULE__)
  end

  def search_results!(interaction) do
    search =
      interaction.data.options
      |> Enum.find_value(fn option ->
        if option.name == "search" do
          option.value
        end
      end)

    type =
      interaction.data.options
      |> Enum.find_value(fn option ->
        if option.name == "type" do
          option.value
        end
      end)

    library =
      interaction.data.options
      |> Enum.find_value(fn option ->
        if option.name == "library" do
          option.value
        end
      end)

    libraries =
      AshHq.Docs.Library.read!()
      |> Enum.filter(& &1.latest_version_id)

    library_version_ids =
      if library do
        case Enum.find(libraries, &(&1.name == library)) do
          nil ->
            []

          library ->
            [library.latest_version_id]
        end
      else
        Enum.map(libraries, & &1.latest_version_id)
      end

    input =
      if type do
        %{types: [type]}
      else
        %{}
      end

    %{result: item_list} = AshHq.Docs.Search.run!(search, library_version_ids, input)

    result_type =
      if type do
        "#{type} results"
      else
        "results"
      end

    library =
      if library do
        "#{library}"
      else
        "all libraries"
      end

    url = AshHqWeb.Endpoint.url()

    if item_list do
      item_list = Enum.take(item_list, 10)

      count =
        case Enum.count(item_list) do
          10 ->
            "the top 10"

          other ->
            "#{other}"
        end

      """
      Found #{count} #{result_type} in #{library}:

      #{Enum.map_join(item_list, "\n", &render_search_result(&1, url))}
      """
    else
      "Something went wrong."
    end
  end

  defp render_search_result(item, url) do
    link = Path.join(url, AshHqWeb.DocRoutes.doc_link(item))

    "* #{item.name}: #{link}"
  end

  def handle_event({:INTERACTION_CREATE, %Nostrum.Struct.Interaction{} = interaction, _ws_state}) do
    response = %{
      # ChannelMessageWithSource
      type: 4,
      data: %{
        content: search_results!(interaction)
      }
    }

    Nostrum.Api.create_interaction_response(interaction, response)
  end

  def handle_event({:READY, _msg, _ws_state}) do
    rebuild()
  end

  # Default event handler, if you don't include this, your consumer WILL crash if
  # you don't have a method definition for each event type.
  def handle_event(_event) do
    :noop
  end

  def rebuild do
    libraries =
      AshHq.Docs.Library.read!()
      |> Enum.filter(& &1.latest_library_version)

    build_search_action(libraries)
  end

  defp build_search_action(libraries) do
    library_names =
      libraries
      |> Enum.map(& &1.name)

    command = %{
      name: "ash_hq_search",
      description: "Search AshHq Documentation",
      options: [
        %{
          # ApplicationCommandType::STRING
          type: 3,
          name: "search",
          description: "what you want to search for",
          required: true
        },
        %{
          # ApplicationCommandType::STRING
          type: 3,
          name: "type",
          description: "What type of thing you want to search for. Defaults to everything.",
          required: false,
          choices:
            Enum.map(AshHq.Docs.Extensions.Search.Types.types(), fn type ->
              %{
                name: String.downcase(type),
                description: "Search only for #{String.downcase(type)} items.",
                value: type
              }
            end)
        },
        %{
          # ApplicationCommandType::STRING
          type: 3,
          name: "library",
          description: "Which library you'd like to search. Defaults to all libraries.",
          required: false,
          choices:
            Enum.map(library_names, fn name ->
              %{
                name: name,
                description: "Search only in the #{name} library.",
                value: name
              }
            end)
        }
      ]
    }

    Nostrum.Api.create_guild_application_command(AshHq.Discord.Poller.server_id(), command)
  end
end
