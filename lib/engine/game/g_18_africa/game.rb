# frozen_string_literal: true

require_relative 'meta'
require_relative 'map'
require_relative 'entities'
require_relative 'corporation'
require_relative 'player'
require_relative 'step/card_selection'
require_relative 'step/initial_auction'
require_relative 'step/buy_sell_certificates'
require_relative 'step/dividend'
require_relative 'step/buy_train'
require_relative 'step/track'
require_relative 'step/corporate_stock'
require_relative 'step/concession_auction'
require_relative 'step/assign_concession'
require_relative 'step/token'
require_relative 'step/priority_deal'
require_relative '../base'

module Engine
  module Game
    module G18Africa
      class Game < Game::Base
        include_meta(G18Africa::Meta)
        include Entities
        include Map

        attr_reader :bank_deck, :bank_discard, :auction_cards, :concession_right

        PLAYER_CLASS = G18Africa::Player
        CORPORATION_CLASS = G18Africa::Corporation

        CURRENCY_FORMAT_STR = '£%s'
        BANK_CASH = 14_000
        BANKRUPTCY_ALLOWED = false

        STARTING_CASH = { 2 => 782, 3 => 694, 4 => 606, 5 => 518 }.freeze

        # Certificate limit by number of remaining companies: none, one or two+ closed [2.4]
        CERT_LIMIT = {
          2 => { 7 => 28, 6 => 23, 5 => 19 },
          3 => { 9 => 24, 8 => 21, 7 => 18 },
          4 => { 9 => 18, 8 => 16, 7 => 14 },
          5 => { 9 => 15, 8 => 13, 7 => 11 },
        }.freeze

        # Number of companies chosen at random for the game [1.3]
        CORPORATIONS_IN_GAME = { 2 => 7, 3 => 9, 4 => 9, 5 => 9 }.freeze

        # Shares/Privates dealt to each player; half of them are kept [1.3]
        CERTS_DEALT = { 2 => 16, 3 => 14, 4 => 12, 5 => 10 }.freeze

        NUM_BONDS = 25
        BOND_PRICE = 100

        # Multiple shares may be bought from the Bank Pool at or below this Market Value [2.2]
        MULTIPLE_BUY_MAX_PRICE = 61

        # Cards revealed from the Bank Deck in a single purchase [2.2]
        MAX_DECK_PURCHASES = 3

        # Economy by number of Shares/Privates in the Bank Pool [3.4.7]
        ECONOMY_NAMES = { boom: 'Boom', recovery: 'Recovery', recession: 'Recession', depression: 'Depression' }.freeze
        ECONOMY_CITY_DELTA = { boom: 20, recovery: 0, recession: -10, depression: -20 }.freeze
        ECONOMY_TOWN_DELTA = { boom: 0, recovery: 0, recession: -10, depression: -20 }.freeze
        BOND_PAYOUT = { boom: 10, recovery: 15, recession: 30, depression: 40 }.freeze
        # The first two Operating Rounds are played in Recovery [3.4.7]
        FIXED_RECOVERY_ORS = 2

        # Value of a Variable City when no Non-Variable City is on the route [3.4.4]
        VARIABLE_CITY_DEFAULT = 20

        # Trains ignoring Recessions and Depressions / allowed to start and end in towns [3.4.3]
        ECONOMY_PROOF_TRAINS = %w[3+3T].freeze
        TOWN_END_TRAINS = %w[3+3T 4+4+4T].freeze

        CAPITALIZATION = :incremental
        HOME_TOKEN_TIMING = :float
        # Tokens displaced by laying #10 on a double City are placed by their owners [3.3.1]
        TOKEN_PLACEMENT_ON_TILE_LAY_ENTITY = :owner
        MUST_BUY_TRAIN = :never
        # New track must be reachable, upgrades must use new track or change a City/Town [3.2]
        TRACK_RESTRICTION = :semi_restrictive

        # Nothing done in the Stock Round affects the Market Value [7]
        SELL_BUY_ORDER = :sell_buy
        SELL_MOVEMENT = :none
        POOL_SHARE_DROP = :none
        SOLD_OUT_INCREASE = false
        MUST_SELL_IN_BLOCKS = false
        MARKET_SHARE_LIMIT = 100

        GAME_END_CHECK = { bank: :current_or, stock_market: :current_or }.freeze

        # Up to four yellow tiles or a single upgrade [3.2]
        TILE_LAYS = [
          { lay: true, upgrade: true },
          { lay: :not_if_upgraded, upgrade: false },
          { lay: :not_if_upgraded, upgrade: false },
          { lay: :not_if_upgraded, upgrade: false },
        ].freeze

        MARKET = [
          %w[0c 5 10 22 34 45 56 58 61p 64p 67p 71p 76p 82p 90p 100p 112 126 142 160 180 205 230 255
             280 300 320 340 360 380 400e 420e 440e 460e],
        ].freeze

        # All tiles are available from the start and the train limit is always 2 [7].
        # After the last 4E is bought every train type becomes available [3.6.1].
        PHASES = [
          { name: '2', train_limit: 2, tiles: %i[yellow green brown gray], operating_rounds: 2 },
          { name: '3', on: '3', train_limit: 2, tiles: %i[yellow green brown gray], operating_rounds: 2 },
          { name: '4E', on: '4E', train_limit: 2, tiles: %i[yellow green brown gray], operating_rounds: 2 },
          { name: 'All', train_limit: 2, tiles: %i[yellow green brown gray], operating_rounds: 2 },
        ].freeze

        # Towns never count against the distance; only Cities do [3.4.1].
        # 'E' trains visit any number of Cities and count the best four stops [3.4.3].
        TRAINS = [
          {
            name: '2',
            salvage: 180,
            distance: [{ 'nodes' => %w[city offboard], 'pay' => 2, 'visit' => 2 },
                       { 'nodes' => ['town'], 'pay' => 99, 'visit' => 99 }],
            price: 180,
            num: 6,
          },
          {
            name: '3',
            salvage: 180,
            distance: [{ 'nodes' => %w[city offboard], 'pay' => 3, 'visit' => 3 },
                       { 'nodes' => ['town'], 'pay' => 99, 'visit' => 99 }],
            price: 300,
            num: 4,
          },
          {
            name: '4E',
            salvage: 300,
            distance: [{ 'nodes' => %w[city offboard town], 'pay' => 4, 'visit' => 99 }],
            requires_token: false,
            price: 450,
            num: 3,
            events: [{ 'type' => 'all_trains_available', 'when' => 3 }],
          },
          {
            name: '3+3',
            salvage: 500,
            distance: [{ 'nodes' => %w[city offboard], 'pay' => 3, 'visit' => 3 },
                       { 'nodes' => ['town'], 'pay' => 99, 'visit' => 99 }],
            multiplier: 2,
            price: 700,
            num: 3,
            available_on: 'All',
          },
          {
            name: '3+3T',
            salvage: 650,
            distance: [{ 'nodes' => %w[city offboard], 'pay' => 3, 'visit' => 3 },
                       { 'nodes' => ['town'], 'pay' => 99, 'visit' => 99 }],
            multiplier: 2,
            price: 850,
            num: 3,
            available_on: 'All',
          },
          {
            name: '4+4+4E',
            salvage: 750,
            distance: [{ 'nodes' => %w[city offboard town], 'pay' => 4, 'visit' => 99 }],
            requires_token: false,
            multiplier: 3,
            price: 1000,
            num: 3,
            available_on: 'All',
          },
          {
            name: '4+4+4T',
            salvage: 850,
            distance: [{ 'nodes' => %w[city offboard], 'pay' => 4, 'visit' => 4 },
                       { 'nodes' => ['town'], 'pay' => 99, 'visit' => 99 }],
            multiplier: 3,
            price: 1200,
            num: 3,
            available_on: 'All',
          },
        ].freeze

        # Selling a train returns it to the Bank for the amount in parentheses [3.6.3]
        def sell_train_to_bank(operator, train)
          price = train.salvage
          @bank.spend(price, operator)
          @depot.reclaim_train(train)
          @log << "#{operator.name} sells a #{train.name} train to the Bank for #{format_currency(price)}"
        end

        def event_all_trains_available!
          @log << '-- The last 4E has been bought: all trains are now available --'
          @phase.next!
          @depot.depot_trains(clear: true)
        end

        def num_trains(train)
          # With two players, remove one '2' and one '3' train [1.2]
          return train[:num] - 1 if @players.size == 2 && %w[2 3].include?(train[:name])

          super
        end

        def setup_preround
          remove_unused_corporations!
          setup_corporation_prices
          create_bonds
          deal_cards
          create_concessions
        end

        def setup
          remove_home_reservations(@removals)
          reserve_double_city_hexes
          mark_commodities
          # Tangier and Casablanca start connected to each other, no bonus for them [3.2.4]
          @connected_cities = connected_city_keys
        end

        # Commodity locations get a diamond, destination ports a plaque with the bonus and the resource
        # (like 18India); both are sticky and stay when tiles are laid [3.4.5]
        def mark_commodities
          CONCESSIONS.each do |id, data|
            add_sticky_icon(data[:commodity], id.downcase)
            data[:ports].each { |port| add_sticky_icon(port, "#{id.downcase}-#{data[:bonus]}") }
          end
        end

        def add_sticky_icon(hex_id, image)
          hex_by_id(hex_id).tile.icons << Part::Icon.new("18_africa/#{image}", nil, true, nil, true, large: true)
        end

        # Commodity diamonds and port plaques are drawn without the round background of large icons,
        # so they cannot be mistaken for tokens
        def decorate_marker(icon)
          return unless CONCESSIONS.key?(icon.name.split('-').first.upcase)

          { shape: :none }
        end

        # ----- Pre-printed yellow double Cities J21 and M32 [3.3.1]

        DOUBLE_CITY_HEXES = %w[J21 M32].freeze

        # Neither City is tied to a Company: the hex is reserved, so no other Company may
        # token there unless room is left for the Companies starting there
        def reserve_double_city_hexes
          DOUBLE_CITY_HEXES.each do |id|
            tile = hex_by_id(id).tile
            tile.cities.each do |city|
              city.reservations.compact.each { |corporation| tile.reservations << corporation }
              city.remove_all_reservations!
            end
          end
        end

        # Once one City of a double City is taken and the other Company has yet to start, the free City is its
        # home: it is reserved there too, so the map shows the Company in that City on every tile. While
        # tokens wait to be re-placed after #10 the reservation is lifted, the Company laying #10 chooses first.
        def update_double_city_reservations
          DOUBLE_CITY_HEXES.each do |id|
            hex = hex_by_id(id)
            tile = hex.tile
            waiting = tile.reservations
            tile.cities.each { |city| waiting.each { |corporation| city.reservations.delete(corporation) } }
            next if waiting.size != 1 || pending_token_on?(hex)

            free = tile.cities.select { |city| city.tokens.compact.empty? }
            free.first.add_reservation!(waiting.first) if free.size == 1
          end
        end

        def pending_token_on?(hex)
          @round.respond_to?(:pending_tokens) && @round.pending_tokens.any? { |p| p[:hexes].include?(hex) }
        end

        def action_processed(action)
          super
          update_double_city_reservations
        end

        # The hex-level label is only needed while the Company's City is not known yet
        def render_hex_reservation?(corporation)
          hex_by_id(corporation.coordinates).tile.cities.none? { |city| city.reserved_by?(corporation) }
        end

        def place_home_token(corporation)
          return super unless DOUBLE_CITY_HEXES.include?(corporation.coordinates)
          return if corporation.tokens.first&.used

          hex = hex_by_id(corporation.coordinates)
          tile = hex.tile
          free = tile.cities.select { |city| city.tokens.compact.empty? }
          token = corporation.find_token_by_type
          tile.reservations.delete(corporation)

          # With track already laid and both Cities free, the Company chooses its City
          if !tile.paths.empty? && free.size > 1
            @log << "#{corporation.name} must choose a City in #{hex.location_name} for its home token"
            @round.pending_tokens << { entity: corporation, hexes: [hex], token: token }
            @round.clear_cache!
            return
          end

          city = free.find { |c| c.index == corporation.city } || free.first
          @log << "#{corporation.name} places a token on #{hex.name}"
          city.place_token(corporation, token)
          clear_graph
        end

        # Shuffle the 17 charters and keep 9 of them (7 with two players) [1.3]
        def remove_unused_corporations!
          keep = CORPORATIONS_IN_GAME[@players.size]
          removed = @corporations.sort_by { rand }.drop(keep)
          removed.each do |corporation|
            @corporations.delete(corporation)
            corporation.close!
            @removals << corporation
          end
          @log << "Companies removed from the game: #{removed.map(&:name).sort.join(', ')}"
        end

        # Starting spaces of removed Companies are not reserved [3.3.1]
        def remove_home_reservations(corporations)
          corporations.each do |corporation|
            hex_by_id(corporation.coordinates).tile.cities.each do |city|
              city.reservations.delete(corporation)
            end
          end
        end

        # Shares are only bought through cards at the printed price; the Share Price
        # marker is placed on the Stock Track when the Company starts [2.3]
        def setup_corporation_prices
          @corporations.each do |corporation|
            price = @stock_market.par_prices.find { |p| p.price == CORPORATION_PRICES[corporation.id] }
            @stock_market.set_par(corporation, price)
            corporation.share_price.corporations.delete(corporation)
            corporation.ipoed = true
            corporation.ipo_shares.each { |share| share.buyable = false }
          end
        end

        def create_bonds
          @bonds = Array.new(NUM_BONDS) do |index|
            Company.new(
              sym: "BOND#{index + 1}",
              name: 'Government Bond',
              value: BOND_PRICE,
              desc: 'Pays out at the start of each Operating Round depending on the Economy. '\
                    'Does not count against the Certificate Limit.',
              type: :bond,
            )
          end
          @bonds.each do |bond|
            bond.owner = @bank
            @bank.companies << bond
          end
          @companies.concat(@bonds)
        end

        # Every share certificate is represented by a card with the same id as the share
        # Companies sharing a pre-printed double City start in their own City of the hex [6]
        HOME_CITY_NAMES = {
          'COR' => 'Brazzaville', 'CNR' => 'Kinshasa', 'CSAR' => 'Pretoria', 'NZA' => 'Johannesburg'
        }.freeze

        def home_description(corporation)
          name = HOME_CITY_NAMES[corporation.id] || LOCATION_NAMES[corporation.coordinates]
          "Home: #{name} (#{corporation.coordinates})"
        end

        def create_share_cards
          @corporations.flat_map do |corporation|
            corporation.ipo_shares.map do |share|
              director = share.president
              Company.new(
                sym: share.id,
                name: director ? "#{corporation.id} Director" : "#{corporation.id} Share",
                value: CORPORATION_PRICES[corporation.id] * share.percent / 10,
                desc: "#{share.percent}% of #{corporation.name}#{director ? " (Director's Certificate)" : ''}. "\
                      "#{home_description(corporation)}",
                type: director ? :director : :share,
                color: corporation.color,
                text_color: corporation.text_color,
              )
            end
          end
        end

        def deal_cards
          share_cards = create_share_cards
          @companies.concat(share_cards)

          deck = (share_cards + privates).sort_by { rand }
          @players.each { |player| player.hand = [] }

          # Simpson variant: every player starts with one Director's Certificate [10]
          if @optional_rules.include?(:simpson)
            directors = deck.select { |c| c.type == :director }.sort_by { rand }
            @players.each do |player|
              director = directors.shift
              deck.delete(director)
              player.hand << director
            end
            deck = deck.sort_by { rand }
          end

          @dealt_hands = {}
          @players.each do |player|
            player.hand.concat(deck.shift(CERTS_DEALT[@players.size] - player.hand.size))
            @dealt_hands[player] = player.hand.dup
            sort_hand!(player)
          end
          @bank_deck = deck
          @bank_discard = []
          @auction_cards = []
        end

        def privates
          @companies.select { |c| c.type == :private }
        end

        # Display order of cards: companies alphabetically by abbreviation with the Director's
        # Certificate first, Privates last
        def card_sort_key(card)
          return [1, card.sym, 0, ''] unless share_card?(card)

          [0, card.id.split('_').first, card.type == :director ? 0 : 1, card.id]
        end

        # Display group of a card: its company's abbreviation, or one group for all Privates
        def card_group(card)
          share_card?(card) ? card.id.split('_').first : :private
        end

        # The order of a hand has no meaning in the rules, so it is kept sorted for display
        def sort_hand!(player)
          player.hand.sort_by! { |card| card_sort_key(card) }
        end

        # Cards in the order they were dealt; the discards keep this order so that shuffling them
        # gives the same result as before hands were sorted for display
        def dealt_order(player, cards)
          (@dealt_hands[player] || []).select { |card| cards.include?(card) }
        end

        def share_card?(card)
          %i[share director].include?(card.type)
        end

        def card_share(card)
          share_by_id(card.id)
        end

        def bonds_in_bank
          @bank.companies.select { |c| c.type == :bond }
        end

        # Shares and Privates count; Bonds, cards in hand and unassigned Concessions do not [2.4]
        def num_certs(entity)
          super - entity.companies.count { |c| c.type != :private }
        end

        # ----- Bank Deck and Bank Discard [2.2.1]

        def top_of_discard
          @bank_discard.last
        end

        def top_of_deck
          reshuffle_discard_into_deck if @bank_deck.empty?
          @bank_deck.first
        end

        def flip_top_card!
          card = top_of_deck
          return unless card

          @bank_deck.delete(card)
          @bank_discard << card
          @log << "#{card.name} is revealed from the Bank Deck onto the Bank Discard"
          reshuffle_discard_into_deck if @bank_deck.empty?
        end

        def reshuffle_discard_into_deck
          return if @bank_discard.empty?

          @log << 'The Bank Deck is empty; the Bank Discard is shuffled to form a new Bank Deck'
          @bank_deck = @bank_discard.sort_by { rand }
          @bank_discard = []
          # the top card starts a new Bank Discard, unless it is the only card left
          return if @bank_deck.size < 2

          card = @bank_deck.shift
          @bank_discard << card
          @log << "#{card.name} is revealed from the Bank Deck onto the Bank Discard"
        end

        # With three or fewer cards left in Deck and Discard, all of them are displayed face up [2.2.1]
        def bank_cards_face_up?
          (@bank_deck.size + @bank_discard.size) <= MAX_DECK_PURCHASES
        end

        def remove_card(card)
          @players.each { |p| p.hand.delete(card) }
          @bank_deck.delete(card)
          @bank_discard.delete(card)
          @auction_cards.delete(card)
        end

        # ----- Buying certificates

        def buy_card(player, card, source)
          remove_card(card)
          price = card.value

          @log << "#{player.name} buys #{card.name} from #{source} for #{format_currency(price)}"
          if share_card?(card)
            buy_share_from_card(player, card_share(card), price)
          else
            card.owner = player
            player.companies << card
            player.spend(price, @bank)
            @bank.companies.delete(card)
          end
        end

        # Unless bought from the Bank Pool, the printed cost goes to the Company's Treasury [2.2.2]
        def buy_share_from_card(player, share, price)
          corporation = share.corporation
          was_started = corporation.floated?
          share.buyable = true
          @share_pool.transfer_shares(share.to_bundle, player, spender: player, receiver: corporation, price: price,
                                                               allow_president_change: false)
          corporation.ordinary_shares_bought += 1 unless share.president
          start_corporation(corporation) if !was_started && corporation.floated?
          update_control(corporation, buyer: player)
        end

        # Shares from the Bank Pool cost the Market Value, paid to the Bank [2.2.2]
        def buy_pool_shares(player, bundle)
          corporation = bundle.corporation
          was_started = corporation.floated?
          price = bundle.price
          @share_pool.transfer_shares(bundle, player, spender: player, receiver: @bank, price: price,
                                                      allow_president_change: false)
          corporation.ordinary_shares_bought += bundle.shares.size
          @log << "#{player.name} buys #{bundle.shares.size} share(s) of #{corporation.name} from the Bank Pool "\
                  "for #{format_currency(price)}"
          start_corporation(corporation) if !was_started && corporation.floated?
          update_control(corporation)
        end

        # The Director's Certificate is never sold directly: another holder with at least two shares, who holds
        # the most shares after the sale, exchanges two of them for it [2.1]
        def director_exchange_target(seller, corporation, sold_shares)
          remaining = corporation.num_shares_held_by(seller) - sold_shares
          holders = (@players + @corporations).reject { |h| [seller, corporation].include?(h) }
          counts = holders.to_h { |h| [h, corporation.num_shares_held_by(h)] }
          max = counts.values.max || 0
          return if max < 2 || max < remaining

          first_clockwise_from(seller, counts.select { |_, count| count == max }.keys)
        end

        # Selling never moves the Share Price [7]; unstarted Companies sell at the printed price [2.1]
        def sell_shares_and_change_price(bundle, **_kwargs)
          corporation = bundle.corporation
          seller = bundle.owner
          price = bundle.price
          bundle = exchange_director_before_sale(bundle) if bundle.presidents_share
          @share_pool.transfer_shares(bundle, @share_pool, spender: @bank, receiver: seller, price: price,
                                                           allow_president_change: false)
          @log << "#{seller.name} sells #{bundle.shares.size} share(s) of #{corporation.name} to the Bank Pool "\
                  "for #{format_currency(price)}"
          update_control(corporation)
        end

        def exchange_director_before_sale(bundle)
          corporation = bundle.corporation
          seller = bundle.owner
          num_shares = bundle.percent / corporation.share_percent
          target = director_exchange_target(seller, corporation, num_shares)
          raise GameError, "Nobody can take over the Director's Certificate of #{corporation.name}" unless target

          @share_pool.change_president(corporation.presidents_share, seller, target)
          @log << "#{target.name} exchanges two shares with #{seller.name} for the Director's Certificate "\
                  "of #{corporation.name}"
          set_controller(corporation, target, 'Director')
          ShareBundle.new(seller.shares_of(corporation).reject(&:president).take(num_shares))
        end

        def stock_round_number
          @stock_round_number || 0
        end

        # The Concession Auction takes place after the first set of Operating Rounds [1.5].
        # At the start of a Stock Round the owner of Madianos Olive Groves may take the Priority Deal [5]
        def new_stock_round
          if stock_round_number == 1 && !@concessions_auctioned
            @concessions_auctioned = true
            @log << '-- Concession Auction --'
            return Round::ConcessionAuction.new(self, [G18Africa::Step::ConcessionAuction])
          end

          if stock_round_number >= 1 && @priority_offered_for != stock_round_number && private_usable?(nil, 'P6')
            @priority_offered_for = stock_round_number
            return Round::PriorityDeal.new(self, [G18Africa::Step::PriorityDeal])
          end

          @stock_round_number = stock_round_number + 1
          super
        end

        def start_corporation(corporation)
          @log << "#{corporation.name} starts. Share Price marker placed at #{format_currency(corporation.share_price.price)}"
          # New markers are placed below markers already on the space [2.3]
          corporation.share_price.corporations << corporation
          place_home_token(corporation)
          # tokens placed outside a token step must invalidate the cached route graph
          clear_graph
        end

        # ----- Director and Manager [2.3]

        def update_control(corporation, buyer: nil)
          holders = @players + @corporations.reject { |c| c == corporation }
          counts = holders.to_h { |h| [h, corporation.num_shares_held_by(h)] }
          @control_checks = (@control_checks || 0) + 1
          corporation.track_holdings(counts, @control_checks)
          return unless corporation.floated?

          if corporation.director_in_play?
            update_director(corporation, counts, buyer)
          else
            update_manager(corporation, counts)
          end
        end

        def update_director(corporation, counts, buyer)
          director_share = corporation.presidents_share
          director = director_share.owner
          previous = corporation.owner

          # The Director's Certificate just entered play: a Manager who has not been surpassed exchanges for it
          if director == buyer && previous&.player? && previous != buyer && counts[previous] >= counts[buyer]
            swap_director(corporation, previous)
            director = previous
          end

          max = counts.values.max
          if counts[director] < max
            new_director = first_clockwise_from(director, counts.select { |_, v| v == max }.keys)
            swap_director(corporation, new_director)
            director = new_director
          end
          set_controller(corporation, director, 'Director')
        end

        def update_manager(corporation, counts)
          manager = corporation.owner if corporation.owner && corporation.owner != corporation
          max = counts.values.max
          return set_controller(corporation, manager, 'Manager') if manager && counts[manager] >= max

          candidates = counts.select { |_, v| v == max }.keys
          new_manager =
            if manager
              first_clockwise_from(manager, candidates)
            else
              # The first among tied players to have reached the tied total
              candidates.min_by { |p| corporation.share_holders_reached_at(p) }
            end
          set_controller(corporation, new_manager, 'Manager')
        end

        def swap_director(corporation, new_director)
          @share_pool.change_president(corporation.presidents_share, corporation.presidents_share.owner, new_director)
        end

        def set_controller(corporation, player, title)
          return if corporation.owner == player

          corporation.owner = player
          @log << "#{player.name} becomes the #{title} of #{corporation.name}"
        end

        # Ties: players clockwise from the previous controller (or the player behind a
        # controlling Company), then Companies in decreasing Market Value [2.1, 3.7]
        def first_clockwise_from(previous, candidates)
          player = previous&.player? ? previous : previous&.player
          index = @players.index(player) || 0
          companies = @corporations.select(&:floated?).sort_by { |c| -c.share_price.price }
          (@players.rotate(index + 1) + companies).find { |h| candidates.include?(h) }
        end

        # ----- Economy [3.4.7]

        def bank_pool_certificates
          @share_pool.shares.size + @bank.companies.count { |c| c.type == :private }
        end

        def economy
          economy_for(operating_round_number)
        end

        def economy_for(or_number)
          return :recovery if or_number <= FIXED_RECOVERY_ORS

          case bank_pool_certificates
          when 0 then :boom
          when 1..2 then :recovery
          when 3..6 then :recession
          else :depression
          end
        end

        # Outside an Operating Round the display shows the Economy of the next Operating Round
        def displayed_or_number
          @round&.operating? ? operating_round_number : operating_round_number + 1
        end

        def displayed_economy
          economy_for(displayed_or_number)
        end

        def economy_description
          reason =
            if displayed_or_number <= FIXED_RECOVERY_ORS
              "fixed in ORs 1-#{FIXED_RECOVERY_ORS}"
            else
              "#{bank_pool_certificates} in Bank Pool"
            end
          "Economy: #{ECONOMY_NAMES[displayed_economy]} (#{reason})"
        end

        def round_phase_string
          "#{super} - #{economy_description}"
        end

        def economy_name
          ECONOMY_NAMES[economy]
        end

        def operating_round_number
          @operating_round_number || 0
        end

        def new_operating_round(round_num = 1)
          @operating_round_number = operating_round_number + 1
          super
        end

        # Privates pay their income, Bonds pay depending on the Economy; in a Depression
        # every Share Price marker moves back one space [3]
        def payout_companies(ignore: [])
          super
          payout_bonds
          depression_price_drop if economy == :depression
        end

        def payout_bonds
          amount = BOND_PAYOUT[economy]
          (@players + @corporations).each do |owner|
            bonds = owner.companies.count { |c| c.type == :bond }
            next if bonds.zero?

            @bank.spend(amount * bonds, owner)
            @log << "#{owner.name} collects #{format_currency(amount * bonds)} from #{bonds} Bond(s) "\
                    "(#{economy_name})"
          end
        end

        def depression_price_drop
          @log << 'Depression: every Share Price marker moves back one space'
          @corporations.select(&:floated?).each do |corporation|
            old_price = corporation.share_price
            @stock_market.move_left(corporation)
            log_share_price(corporation, old_price)
          end
          close_corporations_in_close_cell!
        end

        # ----- Revenue [3.4]

        def variable_city?(stop)
          stop.city? && VARIABLE_CITY_MODIFIERS.key?(stop.hex.id)
        end

        def stop_value(stop, route, current_economy)
          [stop.route_revenue(route.phase, route.train) + economy_delta(stop, route, current_economy), 0].max
        end

        def economy_delta(stop, route, current_economy)
          delta = stop.city? ? ECONOMY_CITY_DELTA[current_economy] : ECONOMY_TOWN_DELTA[current_economy]
          delta.negative? && ECONOMY_PROOF_TRAINS.include?(route.train.name) ? 0 : delta
        end

        # A Variable City is worth the best Non-Variable City on the route, counted or not, plus its modifier
        def variable_city_value(stop, route, current_economy)
          _, best = best_non_variable_city(route, current_economy)
          best ? best + VARIABLE_CITY_MODIFIERS[stop.hex.id] : VARIABLE_CITY_DEFAULT
        end

        def best_non_variable_city(route, current_economy)
          route.visited_stops
               .select { |s| s.city? && !variable_city?(s) }
               .map { |s| [s, stop_value(s, route, current_economy)] }
               .max_by { |_, value| value }
        end

        def revenue_for(route, stops)
          current_economy = economy
          value = stops.sum do |stop|
            variable_city?(stop) ? variable_city_value(stop, route, current_economy) : stop_value(stop, route, current_economy)
          end
          (value * (route.train.multiplier || 1)) + route_bonus(route)
        end

        # Bonuses are neither multiplied by trains nor affected by the Economy [3.4.5, 3.4.6]
        def route_bonus(route)
          route_bonuses(route).sum { |_, amount| amount }
        end

        def route_bonuses(route)
          transcontinental_bonuses(route) + concession_bonuses(route)
        end

        # ----- Private abilities [5]

        # Each ability can be used once per game; the Private keeps its income afterwards
        def private_usable?(corporation, sym)
          company = company_by_id(sym)
          return false if !company || company.closed? || used_private_ability?(sym)

          owner = company.owner
          return owner&.player? && !owner.bankrupt if corporation.nil?
          # Madianos Olive Groves can be owned, but not used by a Company
          return false if sym == 'P6'

          owner == corporation || (owner&.player? && corporation.player == owner)
        end

        def used_private_ability?(sym)
          (@used_private_abilities || []).include?(sym)
        end

        def use_private_ability!(sym, user)
          @used_private_abilities = (@used_private_abilities || []) + [sym]
          company = company_by_id(sym)
          company.desc = 'Ability used.'
          @log << "#{user.name} uses the ability of #{company.name}"
        end

        # Jamieson Tropical Timber waives one river cost once switched on for the next lay
        def upgrade_cost(tile, hex, entity, spender)
          cost = super
          return cost if !@round.respond_to?(:free_river) || !@round.free_river

          river = tile.upgrades.select(&:water?).sum(&:cost)
          return cost unless river.positive?

          @round.free_river = false
          use_private_ability!('P4', entity)
          cost - river
        end

        # ----- Concessions [1.5, 3.4.5]

        CONCESSION_NAMES = {
          'MINERALS' => 'Minerals',
          'DATES' => 'Dates',
          'GAS' => 'Natural Gas',
          'OIL' => 'Oil',
          'COPPER' => 'Copper',
          'COTTON' => 'Cotton',
          'GOLD' => 'Gold',
        }.freeze

        def create_concessions
          @concessions = CONCESSIONS.map do |id, data|
            ports = data[:ports].map { |hex| LOCATION_NAMES[hex] }.join(' or ')
            Company.new(
              sym: "C_#{id}",
              name: "#{CONCESSION_NAMES[id]} Concession",
              value: 0,
              desc: "Route including #{LOCATION_NAMES[data[:commodity]]} and #{ports}: "\
                    "+#{format_currency(data[:bonus])} per train",
              type: :concession,
              # lets the Abilities bar offer "Assign to <Company>" [3.4.5]
              abilities: [{ type: 'assign_corporation', owner_type: 'player' }],
            )
          end
          @concession_right = Company.new(
            sym: 'CONCESSION_CHOICE',
            name: 'Choice of a Concession',
            value: 0,
            desc: 'The highest bidder chooses one of the remaining Concessions.',
            type: :concession_right,
          )
          @companies.concat(@concessions + [@concession_right])
        end

        def concession_data(concession)
          CONCESSIONS[concession.id.delete_prefix('C_')]
        end

        def concessions_available
          @concessions.select { |c| c.owner.nil? && !c.closed? }
        end

        def award_concession(player, concession)
          concession.owner = player
          player.companies << concession
          @log << "#{player.name} takes the #{concession.name}"
        end

        def remove_last_concession
          concessions_available.each do |concession|
            concession.close!
            @log << "The #{concession.name} is removed from the game"
          end
        end

        # The Company must be able to run the Concession route: it needs a train and must reach
        # the Commodity and a port
        def can_run_concession?(corporation, concession)
          return false if corporation.trains.empty?

          data = concession_data(concession)
          hexes = graph_for_entity(corporation).connected_hexes(corporation)
          hexes.key?(hex_by_id(data[:commodity])) && data[:ports].any? { |port| hexes.key?(hex_by_id(port)) }
        end

        def assign_concession(corporation, concession)
          owner = concession.owner
          owner.companies.delete(concession)
          concession.owner = corporation
          corporation.companies << concession
          @log << "#{owner.name} assigns the #{concession.name} to #{corporation.name}"
        end

        # Each train including the Commodity and a port earns the bonus, not multiplied by the train
        def concession_bonus(route)
          concession_bonuses(route).sum { |_, amount| amount }
        end

        def concession_bonuses(route)
          hexes = route.all_hexes.map(&:id)
          route.train.owner.companies.select { |c| c.type == :concession }.filter_map do |concession|
            data = concession_data(concession)
            [concession.name, data[:bonus]] if hexes.include?(data[:commodity]) && data[:ports].intersect?(hexes)
          end
        end

        def transcontinental_bonuses(route)
          hexes = route.all_hexes.map(&:id)
          TRANSCONTINENTAL_BONUSES.filter_map do |bonus|
            next unless (bonus[:hexes] - hexes).empty?

            ["#{bonus[:hexes].map { |hex| LOCATION_NAMES[hex] }.join(' - ')} Transcontinental", bonus[:bonus]]
          end
        end

        # Hexes of the route, then how the value of each counted stop came about, then the bonuses
        def revenue_str(route)
          current_economy = economy
          stops = route.stops.map { |stop| stop_revenue_str(stop, route, current_economy) }
          str = "#{route.hexes.map(&:name).join('-')}: #{stops.join(', ')}"
          multiplier = route.train.multiplier || 1
          str += " x#{multiplier}" if multiplier > 1
          route_bonuses(route).each { |name, amount| str += " + #{format_currency(amount)} #{name}" }
          str
        end

        def stop_revenue_str(stop, route, current_economy)
          name = stop.hex.location_name || stop.hex.name
          if variable_city?(stop)
            value = variable_city_value(stop, route, current_economy)
            best, best_value = best_non_variable_city(route, current_economy)
            note = if best
                     "#{best.hex.location_name || best.hex.name} #{format_currency(best_value)} + "\
                       "#{format_currency(VARIABLE_CITY_MODIFIERS[stop.hex.id])}"
                   else
                     'no Non-Variable City'
                   end
            return "#{name} #{format_currency(value)} (#{note})"
          end

          value = stop_value(stop, route, current_economy)
          delta = economy_delta(stop, route, current_economy)
          return "#{name} #{format_currency(value)}" if delta.zero?

          base = format_currency(stop.route_revenue(route.phase, route.train))
          sign = delta.positive? ? '+' : '-'
          "#{name} #{format_currency(value)} (#{base} #{sign} #{format_currency(delta.abs)} #{ECONOMY_NAMES[current_economy]})"
        end

        # At least two Cities; only 'T' trains may start or end in a Town [3.4.1]
        def check_other(route)
          visited = route.visited_stops
          raise GameError, 'Route must include at least two Cities' if visited.count(&:city?) < 2
          return if TOWN_END_TRAINS.include?(route.train.name)
          return if visited.first.city? && visited.last.city?

          raise GameError, 'Route must start and end in a City'
        end

        # ----- Track [3.2]

        # Yellow tiles with a single Town may be upgraded into a green City tile [3.2.3]
        def yellow_town_to_city_upgrade?(from, to)
          from.color == :yellow && from.towns.one? && from.cities.empty? &&
            to.color == :green && to.cities.one? && to.towns.empty?
        end

        def upgrades_to?(from, to, special = false, selected_company: nil)
          return true if yellow_town_to_city_upgrade?(from, to)

          super
        end

        # ----- Connection Bonus [3.2.4]

        # Cities connected by track to at least one other City, ignoring train length and tokens
        def connected_city_keys
          parent = {}
          find = lambda do |k|
            parent[k] ||= k
            root = k
            root = parent[root] until parent[root] == root
            parent[k] = root
          end
          union = ->(a, b) { parent[find.call(a)] = find.call(b) }

          cities = []
          @hexes.each do |hex|
            hex.tile.cities.each { |city| cities << city }
            hex.tile.paths.each do |path|
              keys = path.exits.map { |edge| edge_key(hex, edge) }
              keys.concat(path.nodes.map { |node| node_key(node) })
              keys << [hex.id, :junction] if path.junction
              keys.each_cons(2) { |a, b| union.call(a, b) }
            end
          end

          by_component = cities.group_by { |city| find.call(node_key(city)) }
          by_component.values.select { |group| group.size > 1 }.flatten.map { |city| node_key(city) }
        end

        def edge_key(hex, edge)
          neighbor = hex.neighbors[edge]
          return [hex.id, edge] unless neighbor

          [[hex.id, edge], [neighbor.id, hex.invert(edge)]].min
        end

        def node_key(node)
          [node.hex.id, node.type, node.index]
        end

        def city_for_key(key)
          hex_by_id(key[0]).tile.cities.find { |city| city.index == key[2] }
        end

        # Cities the Company can trace a route to. The graph is rebuilt first so the result never depends on
        # what was cached before (replays skip some checks that build it). A token waiting to be re-placed
        # after #10 was laid counts as present in its hex.
        def reachable_city_keys(entity, include_pending: true)
          clear_graph_for_entity(entity)
          keys = graph_for_entity(entity).connected_nodes(entity).keys.select(&:city?).map { |c| node_key(c) }
          pending_hexes = @round.pending_tokens.select { |p| p[:entity] == entity }.flat_map { |p| p[:hexes] }
          pending_keys = pending_hexes.flat_map { |h| h.tile.cities.map { |c| node_key(c) } }
          include_pending ? (keys + pending_keys).uniq : keys - pending_keys
        end

        # An upgrade may renumber the Cities of a hex (#10 to #35 swaps them in some rotations): carry the
        # connected Cities over to their new index so an upgrade never looks like a new connection.
        def remap_connected_cities(hex, city_map)
          remapped = city_map.filter_map do |old_city, new_city|
            old_key = [hex.id, old_city.type, old_city.index]
            [hex.id, new_city.type, new_city.index] if new_city && @connected_cities.include?(old_key)
          end
          @connected_cities = @connected_cities.reject { |key| key[0] == hex.id } + remapped
        end

        def check_connection_bonus(entity, hex, town_upgrade: false)
          now = connected_city_keys
          newly = now - @connected_cities
          @connected_cities |= now
          return if newly.empty?

          reachable = reachable_city_keys(entity)
          newly.each do |key|
            city = city_for_key(key)
            name = city.hex.location_name || city.hex.id
            if town_upgrade && key[0] == hex.id
              @log << "#{name} was upgraded from a Town and gives no Connection Bonus"
            elsif !reachable.include?(key)
              @log << "#{name} is connected but #{entity.name} cannot reach it: its Connection Bonus is lost"
            else
              amount = variable_city?(city) ? VARIABLE_CITY_DEFAULT : city.max_revenue
              @bank.spend(amount, entity) if amount.positive?
              @log << "#{entity.name} receives a Connection Bonus of #{format_currency(amount)} for #{name}"
            end
          end
        end

        # ----- End of a company's turn

        # A Managed Company without a train that does not buy one falls back two more spaces [2.3, 3.5.1]
        def after_end_of_operating_turn(operator)
          super
          return if !operator.corporation? || operator.closed?
          return if !operator.managed? || !operator.trains.empty?

          old_price = operator.share_price
          2.times { @stock_market.move_left(operator) }
          @log << "#{operator.name} is Managed and has no train"
          log_share_price(operator, old_price)
          close_corporations_in_close_cell!
        end

        # Shares and Privates owned by a closing Company go to the Bank Pool; its cards leave the game [3.5.1]
        def close_corporation(corporation, quiet: false)
          corporation.companies.dup.each do |company|
            corporation.companies.delete(company)
            company.owner = @bank
            @bank.companies << company
          end
          corporation.corporate_shares.dup.each do |share|
            @share_pool.transfer_shares(share.to_bundle, @share_pool, allow_president_change: false)
          end
          @companies.select { |c| share_card?(c) && c.id.start_with?("#{corporation.id}_") }.each { |c| remove_card(c) }
          super
          # its tokens are gone, so routes of other Companies change
          clear_graph
        end

        # ----- Game end [4]

        # A Share is worth its Market Value plus 10% of the Market Value of shares and of the face value
        # of Privates the Company owns, plus 5% of the face value of its trains; each addition is
        # rounded down separately (rule 4 example: 5% of 1030 -> 51, 10% of 237 -> 23)
        def final_share_value(corporation)
          owned_shares = corporation.corporate_shares.sum { |s| s.corporation.share_price.price * s.num_shares }
          owned_privates = corporation.companies.select { |c| c.type == :private }.sum(&:value)
          trains = corporation.trains.sum(&:price)
          corporation.share_price.price + ((owned_shares + owned_privates) / 10) + (trains / 20)
        end

        # Cash, £100 per Bond, face value of Privates and adjusted value of Shares; cards in hand are worth nothing.
        # Concessions variant: £100 less for each Concession never assigned [10]
        def player_value(player)
          value = player.cash + player.companies.sum(&:value) +
                  player.shares.sum { |s| s.num_shares * share_value_for_score(s.corporation) }
          value -= 100 * player.companies.count { |c| c.type == :concession } if @optional_rules.include?(:concessions_penalty)
          value
        end

        # Two player auction variant: 8 of the shuffled discards go back into the Bank Deck and the
        # top 8 Bank Deck cards are auctioned instead [10]
        def two_player_auction_swap
          return if !@optional_rules.include?(:two_player_auction) || @players.size != 2

          @auction_cards.sort_by! { rand }
          returned = @auction_cards.shift(8)
          @bank_deck = (@bank_deck + returned).sort_by { rand }
          @auction_cards.concat(@bank_deck.shift(8))
          @log << '8 discarded cards are shuffled back into the Bank Deck and replaced by 8 cards from it'
        end

        def share_value_for_score(corporation)
          corporation.floated? ? final_share_value(corporation) : CORPORATION_PRICES[corporation.id]
        end

        # ----- View helpers

        # Legend next to the map listing the Transcontinental Routes, like 18India's connection bonuses [3.4.6]
        def show_map_legend?
          true
        end

        def map_legends
          %i[economy_legend transcontinental_legend]
        end

        ECONOMY_POOL_RANGES = { boom: '0', recovery: '1-2', recession: '3-6', depression: '7+' }.freeze

        def economy_delta_str(value)
          return 'printed' if value.zero?

          "#{value.positive? ? '+' : '-'}#{format_currency(value.abs)}"
        end

        # The Economy table of the printed board; the row in effect is highlighted [3.4.7]
        def economy_legend(font_color, yellow, green, _brown, _gray, _red, action_processor: nil)
          cell_style = {
            border: '1px solid',
            color: font_color,
            'text-align': 'center',
            'vertical-align': 'middle',
            height: '28px',
            padding: '0 0.5rem',
          }
          current = displayed_economy
          highlight = { **cell_style, backgroundColor: yellow, color: 'black', 'font-weight': 'bold' }
          header_style = { **cell_style, backgroundColor: green, color: 'black', 'font-weight': 'bold' }

          rows = ECONOMY_NAMES.map do |level, name|
            style = level == current ? highlight : cell_style
            [ECONOMY_POOL_RANGES[level], name, economy_delta_str(ECONOMY_CITY_DELTA[level]),
             economy_delta_str(ECONOMY_TOWN_DELTA[level]), format_currency(BOND_PAYOUT[level])]
              .map { |text| { text: text, props: { style: style } } }
          end
          note_style = { **cell_style, 'text-align': 'left', 'font-size': '80%', padding: '0.2rem 0.5rem' }
          notes = [
            "#{economy_description}.",
            'Shares and Privates in the Bank Pool count; Trains and Bonds do not.',
            "ORs 1-#{FIXED_RECOVERY_ORS} are always played in Recovery.",
            'Depression: every Share Price moves back one space at the start of an OR.',
            'Values never drop below £0. 3+3T trains ignore Recession and Depression.',
          ].map { |text| [{ text: text, props: { attrs: { colspan: 5 }, style: note_style } }] }

          [
            { style: { margin: '0.5rem 0 0.5rem 0', border: '1px solid', borderCollapse: 'collapse' } },
            ['Bank Pool', 'Economy', 'Cities', 'Towns', 'Bonds'].map { |text| { text: text, props: { style: header_style } } },
            *rows,
            *notes,
          ]
        end

        def transcontinental_legend(font_color, _yellow, green, _brown, _gray, _red, action_processor: nil)
          cell_style = {
            border: '1px solid',
            color: font_color,
            'font-weight': 'bold',
            'text-align': 'center',
            'vertical-align': 'middle',
            height: '33px',
            padding: '0 0.5rem',
          }
          rows = TRANSCONTINENTAL_BONUSES.map do |bonus|
            route = bonus[:hexes].map { |hex| "#{LOCATION_NAMES[hex]} (#{hex})" }.join(' ⟷ ')
            [
              { text: route, props: { style: cell_style } },
              { text: format_currency(bonus[:bonus]), props: { style: cell_style } },
            ]
          end

          [
            { style: { margin: '0.5rem 0 0.5rem 0', border: '1px solid', borderCollapse: 'collapse' } },
            [
              {
                text: 'Transcontinental Routes',
                props: { attrs: { colspan: 2 }, style: { **cell_style, backgroundColor: green, color: 'black' } },
              },
            ],
            *rows,
          ]
        end

        ROUND_TITLES = {
          'Draft' => 'Certificate Selection',
          'Auction' => 'Initial Auction',
          'ConcessionAuction' => 'Concession Auction',
          'PriorityDeal' => 'Priority Deal',
        }.freeze

        def round_description(name, round_number = nil)
          super(ROUND_TITLES.fetch(name, name), round_number)
        end

        COMPANY_HEADERS = {
          share: 'SHARE',
          director: "DIRECTOR'S CERTIFICATE",
          bond: 'GOVERNMENT BOND',
          concession: 'CONCESSION',
          concession_right: 'CONCESSION',
        }.freeze

        def company_header(company)
          COMPANY_HEADERS.fetch(company.type, 'PRIVATE COMPANY')
        end

        # A Company starts with its Director's Certificate or three ordinary shares [2.3]
        def float_str(entity)
          return unless entity.corporation?
          return if entity.floated?

          shares = 3 - entity.ordinary_shares_bought
          "Director or #{shares} share#{shares > 1 ? 's' : ''}"
        end

        def show_hidden_hand?
          true
        end

        # Cards in hand have no owner yet; always showing the value keeps the company table's
        # three columns (name, value, income) aligned
        def show_value_of_companies?(_owner)
          true
        end

        def player_card_rows(player)
          ['Cards in hand', player.hand.size.to_s]
        end

        def hand_companies_for_stock_round
          return [] unless @round.stock?

          player = @round.current_entity
          return [] unless player&.player?

          player.hand.sort_by { |card| card_sort_key(card) }
        end

        # The Bank Discard is public information and shown top card first [2]
        def show_ipo_rows?
          true
        end

        def ipo_rows
          [@bank_discard.reverse]
        end

        def ipo_row_title(_row_number)
          "Bank Discard (Bank Deck: #{@bank_deck.size} cards)"
        end

        # Cards other than hand and Bank Discard that can currently be bought
        def buyable_bank_owned_companies
          step = @round.active_step
          if @round.stock? && step.respond_to?(:buyable_companies) && (player = step.current_entity)&.player?
            return step.buyable_companies(player) - player.hand - [top_of_discard]
          end

          @bank.companies.reject { |c| c.type == :bond } + bonds_in_bank.take(1)
        end

        # ----- Rounds

        def init_round
          @log << "-- #{round_description('Certificate Selection', 1)} --"
          @round_counter += 1
          selection_round
        end

        def selection_round
          Engine::Round::Draft.new(self, [G18Africa::Step::CardSelection], reverse_order: false)
        end

        def initial_auction_round
          Engine::Round::Auction.new(self, [G18Africa::Step::InitialAuction])
        end

        def stock_round
          Engine::Round::Stock.new(self, [
            Engine::Step::HomeToken,
            G18Africa::Step::BuySellCertificates,
          ])
        end

        def next_round!
          @round =
            case @round
            when Engine::Round::Draft
              @log << "-- #{round_description('Initial Auction', 1)} --"
              initial_auction_round
            when Round::ConcessionAuction, Round::PriorityDeal
              new_stock_round
            when Engine::Round::Auction
              give_priority_after_auction
              new_stock_round
            else
              return super
            end
        end

        # Priority goes to the player to the left of the player with the least money [1.3]
        def give_priority_after_auction
          least = @players.min_by(&:cash)
          ties = @players.select { |p| p.cash == least.cash }
          poorest = ties.min_by { rand }
          @players.rotate!(@players.index(poorest) + 1)
          @log << "#{@players.first.name} has the Priority Deal"
        end

        def operating_round(round_num)
          Engine::Round::Operating.new(self, [
            G18Africa::Step::AssignConcession,
            Engine::Step::HomeToken,
            G18Africa::Step::Track,
            G18Africa::Step::Token,
            Engine::Step::Route,
            G18Africa::Step::Dividend,
            G18Africa::Step::BuyTrain,
            G18Africa::Step::CorporateSellShares,
            G18Africa::Step::CorporateBuyShares,
          ], round_num: round_num)
        end
      end
    end
  end
end
