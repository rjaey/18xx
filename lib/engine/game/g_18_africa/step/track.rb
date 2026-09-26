# frozen_string_literal: true

require_relative '../../../step/track'

module Engine
  module Game
    module G18Africa
      module Step
        # Up to four yellow tiles or a single upgrade [3.2]:
        # - each further yellow tile continues directly from the previous one, possibly across
        #   pre-printed gray track [3.2.1]
        # - laying stops after a sharp curve (#3, #7), a tile with a City, or connecting to a new City
        # - Cities and Towns may only be upgraded if a train of the Company reaches them [3.2.3]
        # - a Company without track on its home hex may lay its home City tile (or #10 on the
        #   pre-printed yellow double Cities) and continue with further yellow tiles [3.2.2]
        class Track < Engine::Step::Track
          HALTING_TILES = %w[3 7].freeze

          def round_state
            super.merge(last_laid_hex: nil, track_halted: false)
          end

          def setup
            super
            @round.last_laid_hex = nil
            @round.track_halted = false
          end

          def can_lay_tile?(entity)
            return false if @round.track_halted

            super
          end

          def available_hex(entity, hex)
            available = super
            return nil unless available
            return nil if @round.last_laid_hex && !continuation_edges(@round.last_laid_hex).key?(hex)
            return nil if !hex.tile.city_towns.empty? && hex.tile.color != :white && !upgrade_reachable_by_train?(entity, hex)

            available
          end

          def legal_tile_rotation?(entity, hex, tile)
            if (last = @round.last_laid_hex)
              required = continuation_edges(last)[hex]
              return false unless required
              return false unless required.any? { |edge| tile.exits.include?(edge) }
            end

            old_tile = hex.tile
            return town_to_city_rotation?(hex, old_tile, tile) if @game.yellow_town_to_city_upgrade?(old_tile, tile)

            super
          end

          # Laying the home tile (incl. #10 on a pre-printed double City) counts as a yellow lay [3.2.2]
          def track_upgrade?(from, to, hex)
            return false if @home_lay || home_tile_lay?(current_entity, hex, to)

            super
          end

          def process_lay_tile(action)
            entity = action.entity
            hex = action.hex
            tile = action.tile
            home_lay = home_tile_lay?(entity, hex, tile)
            reachable_before = reachable_cities(entity)
            had_town = !hex.tile.towns.empty?

            # the engine asks again after the tile is placed, when the old tile is already gone
            @home_lay = home_lay
            lay_tile_action(action)
            @home_lay = false
            @round.last_laid_hex = hex
            @game.check_connection_bonus(entity, hex, town_upgrade: had_town && !tile.cities.empty?)

            @round.track_halted = halts?(entity, tile, reachable_before, home_lay)
            pass! if @round.track_halted || !can_lay_tile?(entity)
          end

          # When #10 is first laid on a double City and both Companies have started there, the Company
          # that laid it chooses first; otherwise they choose in order of Market Value [3.3.1]
          def update_token!(action, entity, tile, old_tile)
            super
            pending = @round.pending_tokens.select { |p| p[:hexes] == [action.hex] }
            return if pending.size < 2

            layer = entity.company? ? entity.owner : entity
            ordered = pending.each_with_index.sort_by do |p, index|
              [p[:entity] == layer ? 0 : 1, -p[:entity].share_price.price, index]
            end.map(&:first)
            @round.pending_tokens.reject! { |p| pending.include?(p) }
            @round.pending_tokens.concat(ordered)
          end

          private

          def home_tile_lay?(entity, hex, tile)
            return false unless entity&.corporation?
            return false unless @round.num_laid_track.zero?
            return false unless hex.id == entity.coordinates

            old_tile = hex.tile
            old_tile.color == :white || (old_tile.color == :yellow && old_tile.paths.empty? && tile.name == '10')
          end

          def halts?(entity, tile, reachable_before, home_lay)
            return true if HALTING_TILES.include?(tile.name)
            return true if !home_lay && !tile.cities.empty?

            !(reachable_cities(entity) - reachable_before).empty?
          end

          def reachable_cities(entity)
            @game.graph_for_entity(entity).connected_nodes(entity).keys
                 .select(&:city?)
                 .map { |city| [city.hex.id, city.index] }
          end

          # Hexes adjacent to the last laid tile, following pre-printed gray track, with the edge(s)
          # through which the next tile must connect
          def continuation_edges(last_hex)
            result = Hash.new { |h, k| h[k] = [] }
            visited = [last_hex]
            queue = last_hex.tile.exits.map { |edge| [last_hex, edge] }
            until queue.empty?
              hex, edge = queue.shift
              neighbor = hex.neighbors[edge]
              next unless neighbor

              entry = hex.invert(edge)
              if gray_track?(neighbor)
                next if visited.include?(neighbor)

                visited << neighbor
                neighbor.tile.paths.select { |p| p.exits.include?(entry) }.each do |path|
                  (path.exits - [entry]).each { |exit| queue << [neighbor, exit] }
                end
              else
                result[neighbor] << entry
              end
            end
            result
          end

          def gray_track?(hex)
            hex.tile.color == :gray && hex.tile.city_towns.empty? && !hex.tile.paths.empty?
          end

          # A City or Town may only be upgraded if one of the Company's trains can reach it
          def upgrade_reachable_by_train?(entity, hex)
            return false if entity.trains.empty?

            nodes = @game.graph_for_entity(entity).connected_nodes(entity)
            hex.tile.city_towns.any? { |ct| nodes[ct] }
          end

          def town_to_city_rotation?(hex, old_tile, tile)
            return false unless tile.exits.all? { |edge| hex_neighbor_exists?(current_entity, hex, edge) }

            (old_tile.exits - tile.exits).empty?
          end

          # Track may not run off the board or into a blank side of a gray hex [3.2.1]
          def hex_neighbor_exists?(_entity, hex, edge)
            neighbor = hex.neighbors[edge]
            return false unless neighbor
            return true unless neighbor.tile.color == :gray

            neighbor.tile.exits.include?(hex.invert(edge))
          end
        end
      end
    end
  end
end
