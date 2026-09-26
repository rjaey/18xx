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

          # Allen Rock Aggregates: a fifth yellow tile; Thompson Wagon Works: a second upgrade of the
          # same tile; Jamieson Tropical Timber: one free river crossing [5]
          FIFTH_LAY = { lay: true, upgrade: false, cost: 0, upgrade_cost: 0, cannot_reuse_same_hex: false }.freeze
          SECOND_UPGRADE = { lay: false, upgrade: true, cost: 0, upgrade_cost: 0, cannot_reuse_same_hex: false }.freeze

          def round_state
            super.merge(last_laid_hex: nil, track_halted: false, free_river: false)
          end

          def setup
            super
            @round.last_laid_hex = nil
            @round.track_halted = false
            @round.free_river = false
          end

          def actions(entity)
            actions = super
            return actions if actions.empty? || !free_river_available?(entity)

            actions + ['choose']
          end

          def can_lay_tile?(entity)
            return false if @round.track_halted

            super
          end

          def get_tile_lay(entity)
            tile_lay = super
            return tile_lay if tile_lay && (tile_lay[:lay] || tile_lay[:upgrade])

            corporation = get_tile_lay_corporation(entity)
            if @round.upgraded_track
              return SECOND_UPGRADE.dup if @round.num_upgraded_track == 1 && @game.private_usable?(corporation, 'P3')
            elsif tile_lay_index == 4 && @game.private_usable?(corporation, 'P2')
              return FIFTH_LAY.dup
            end
            tile_lay
          end

          def free_river_available?(entity)
            !@round.free_river && @game.private_usable?(entity, 'P4')
          end

          def choice_available?(entity)
            free_river_available?(entity)
          end

          def choice_name
            'Jamieson Tropical Timber'
          end

          def choices
            { 'free_river' => 'The next river crossing is free' }
          end

          def process_choose(_action)
            @round.free_river = true
          end

          def available_hex(entity, hex)
            available = super
            return nil unless available
            return (hex == @round.last_laid_hex ? available : nil) if @round.upgraded_track
            return nil if @round.last_laid_hex && !continuation_edges(@round.last_laid_hex).key?(hex)
            return nil if !hex.tile.city_towns.empty? && hex.tile.color != :white &&
                          !home_hex_without_track?(entity, hex) && !upgrade_reachable_by_train?(entity, hex)

            available
          end

          def legal_tile_rotation?(entity, hex, tile)
            if !@round.upgraded_track && (last = @round.last_laid_hex)
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
            fifth_lay = @round.num_laid_track == 4
            second_upgrade = @round.upgraded_track

            # the engine asks again after the tile is placed, when the old tile is already gone
            @home_lay = home_lay
            lay_tile_action(action)
            @home_lay = false
            @game.use_private_ability!('P2', entity) if fifth_lay
            @game.use_private_ability!('P3', entity) if second_upgrade
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
            return false unless home_hex_without_track?(entity, hex)

            hex.tile.color == :white || tile.name == '10'
          end

          # A Company may build on its home hex while it has no track there, even without a train;
          # on the pre-printed yellow double Cities this means laying #10 [3.2.2]
          def home_hex_without_track?(entity, hex)
            return false unless entity&.corporation?
            return false unless @round.num_laid_track.zero?
            return false unless hex.id == entity.coordinates

            hex.tile.paths.empty? && %i[white yellow].include?(hex.tile.color)
          end

          # Only yellow track laying halts; an upgrade ends the lays anyway [3.2.1]
          def halts?(entity, tile, reachable_before, home_lay)
            return false if tile.color != :yellow && !home_lay
            return true if HALTING_TILES.include?(tile.name)
            return true if !home_lay && !tile.cities.empty?

            !(reachable_cities(entity) - reachable_before).empty?
          end

          def reachable_cities(entity)
            # a token waiting to be re-placed on the laid hex does not make its Cities newly reached
            @game.reachable_city_keys(entity, include_pending: false)
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
