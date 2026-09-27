# frozen_string_literal: true

require 'spec_helper'
require_relative 'spec_helpers'

module Engine
  module Game
    module G18Africa
      describe Game do
        include G18AfricaSpecHelpers

        let(:players) { %w[a b c] }

        context 'with Marrakech-Fez (home D5)' do
          let(:game) { Engine::Game::G18Africa::Game.new(players, id: seed_with('MF')) }
          let(:mf) { game.corporation_by_id('MF') }

          before do
            reach_first_stock_round
            start_with_director(mf)
            finish_first_stock_round
          end

          it 'stops laying after connecting to a City and pays the Connection Bonus' do
            cash = mf.cash
            lay(mf, 'D5', '115', [3]) # home City towards Casablanca
            expect(step).not_to be_a(G18Africa::Step::Track)
            # Marrakech is newly connected; Casablanca was already connected to Tangier
            expect(mf.cash).to eq(cash + 20)
          end

          it 'requires further yellow tiles to continue from the previous one' do
            lay(mf, 'D5', '115', [0]) # home City towards D7
            expect(step).to be_a(G18Africa::Step::Track)
            expect(step.available_hex(mf, game.hex_by_id('E6'))).to be_nil
            expect(step.available_hex(mf, game.hex_by_id('D7'))).to be_truthy

            lay(mf, 'D7', '9', [3, 0])
            expect(step).to be_a(G18Africa::Step::Track)
            expect(step.available_hex(mf, game.hex_by_id('D9'))).to be_truthy
          end

          it 'stops laying after a sharp curve' do
            lay(mf, 'D5', '115', [0])
            lay(mf, 'D7', '7', [3])
            expect(step).not_to be_a(G18Africa::Step::Track)
          end

          it 'allows at most four yellow tiles' do
            lay(mf, 'D5', '115', [0])
            lay(mf, 'D7', '9', [3, 0])
            lay(mf, 'D9', '9', [3, 0])
            lay(mf, 'D11', '9', [3, 0])
            expect(step).not_to be_a(G18Africa::Step::Track)
          end

          it 'lets a Company with a train upgrade a connected Town its train does not reach' do
            # Agadir (C6) has a yellow Town whose track points away from Marrakech
            agadir = game.hex_by_id('C6')
            town = game.tiles.find { |t| t.name == '3' }
            rotation = (0..5).find do |r|
              town.rotate!(r)
              !town.exits.include?(agadir.invert(1))
            end
            town.rotate!(rotation)
            agadir.lay(town)
            lay(mf, 'D5', '115', [1]) # home City towards Agadir
            process('pass', current) while current == mf
            game.buy_train(mf, game.depot.upcoming.first, :free)
            advance until current == mf && step.is_a?(G18Africa::Step::Track)

            nodes = game.graph_for_entity(mf).connected_nodes(mf)
            expect(agadir.tile.towns.none? { |t| nodes[t] }).to be(true)
            expect(step.available_hex(mf, agadir)).to be_truthy
          end

          it 'does not let a Company without a train upgrade a City' do
            lay(mf, 'D5', '115', [0])
            process('pass', mf) while game.round.current_entity == mf
            advance until current == mf
            expect(step.available_hex(mf, game.hex_by_id('D5'))).to be_nil
          end
        end

        context 'with a Company at home on a pre-printed double City' do
          let(:game) { Engine::Game::G18Africa::Game.new(players, id: seed_with('CSAR')) }
          let(:csar) { game.corporation_by_id('CSAR') }

          before do
            reach_first_stock_round
            start_with_director(csar)
            finish_first_stock_round
            process('pass', current) until current == csar
          end

          it 'may lay #10 as its first lay and continue with yellow tiles' do
            lay(csar, 'M32', '10', [])
            if step.is_a?(Engine::Step::HomeToken)
              city = game.hex_by_id('M32').tile.cities.first
              process('place_token', csar, city: city.id, slot: 0, tokener: csar.id)
            end
            expect(step).to be_a(G18Africa::Step::Track)
            expect(step.get_tile_lay(csar)[:lay]).to be(true)
          end
        end

        context 'with both Companies of Pretoria & Johannesburg (M32)' do
          let(:game) { Engine::Game::G18Africa::Game.new(players, id: seed_with('CSAR', 'NZA')) }
          let(:csar) { game.corporation_by_id('CSAR') }
          let(:nza) { game.corporation_by_id('NZA') }
          let(:m32) { game.hex_by_id('M32') }

          before { reach_first_stock_round }

          it 'reserves the hex, and the free City once the other Company has started' do
            expect(m32.tile.cities.flat_map(&:reservations).compact).to be_empty
            expect(m32.tile.reservations).to eq([csar, nza])

            start_with_director(csar)
            other = (game.corporations - [csar, nza]).first
            city = m32.tile.cities.find { |c| c.tokens.compact.empty? }

            expect(m32.tile.reservations).to eq([nza])
            expect(city.reserved_by?(nza)).to be(true)
            game.bank.spend(500, other)
            expect(city.tokenable?(other, tokens: other.find_token_by_type)).to be(false)
          end

          it 'lets the Company that lays #10 choose its City first' do
            start_with_director(csar)
            start_with_director(nza)
            finish_first_stock_round
            process('pass', current) until current == csar

            lay(csar, 'M32', '10', [])
            expect(step).to be_a(Engine::Step::HomeToken)
            expect(game.round.pending_tokens.map { |p| p[:entity] }).to eq([csar, nza])

            cities = m32.tile.cities
            process('place_token', csar, city: cities[1].id, slot: 0, tokener: csar.id)
            process('place_token', nza, city: cities[0].id, slot: 0, tokener: nza.id)
            expect(cities[1].tokened_by?(csar)).to be(true)
            expect(cities[0].tokened_by?(nza)).to be(true)
          end

          it 'shows the Company yet to start in the free City, also on upgraded tiles' do
            start_with_director(csar)
            finish_first_stock_round
            process('pass', current) until current == csar
            nza_city = -> { m32.tile.cities.find { |c| c.reserved_by?(nza) } }
            expect(nza_city.call.tokens.compact).to be_empty # CSAR is in the other City of the pre-printed tile

            lay(csar, 'M32', '10', [])
            expect(nza_city.call).to be_nil # CSAR chooses first
            process('place_token', csar, city: m32.tile.cities[1].id, slot: 0, tokener: csar.id)
            expect(nza_city.call).to eq(m32.tile.cities[0])
            expect(game.render_hex_reservation?(nza)).to be(false)

            process('pass', current) while current == csar
            game.buy_train(csar, game.depot.upcoming.first, :free)
            advance until current == csar && step.is_a?(G18Africa::Step::Track)
            tile = game.tiles.find { |t| t.name == '35' }
            process('lay_tile', csar, hex: 'M32', tile: tile.id, rotation: 3)
            city = nza_city.call
            expect(city).not_to be_nil
            expect(city.tokens.compact).to be_empty

            process('pass', current) until game.round.is_a?(Engine::Round::Stock) || !game.round.operating?
            advance until game.round.is_a?(Engine::Round::Stock)
            start_with_director(nza)
            expect(city.tokened_by?(nza)).to be(true)
            expect(m32.tile.cities.flat_map(&:reservations).compact).to be_empty
          end

          it 'lets a Company choose its City when track was laid before it started' do
            tile = game.tiles.find { |t| t.name == '10' }
            m32.lay(tile)
            start_with_director(csar)
            expect(step).to be_a(Engine::Step::HomeToken)

            city = m32.tile.cities[1]
            process('place_token', csar, city: city.id, slot: 0, tokener: csar.id)
            expect(city.tokened_by?(csar)).to be(true)

            start_with_director(nza)
            expect(m32.tile.cities[0].tokened_by?(nza)).to be(true)
          end
        end

        context 'when upgrading a connected double City' do
          let(:game) { Engine::Game::G18Africa::Game.new(players, id: seed_with('CSAR')) }
          let(:csar) { game.corporation_by_id('CSAR') }
          let(:m32) { game.hex_by_id('M32') }

          before do
            m32.lay(game.tiles.find { |t| t.name == '10' })
            reach_first_stock_round
            start_with_director(csar)
            process('place_token', csar, city: m32.tile.cities[0].id, slot: 0, tokener: csar.id)
            game.buy_train(csar, game.depot.upcoming.first, :free)
            finish_first_stock_round
            process('pass', current) until current == csar
          end

          it 'pays no Connection Bonus when #35 renumbers its Cities' do
            game.instance_variable_set(:@connected_cities, [['M32', 'city', 0]])
            # the connected City (with CSAR's token) becomes City 1 of #35 in rotation 3
            allow(game).to receive(:connected_city_keys) do
              m32.tile.cities.select { |c| c.tokened_by?(csar) }.map { |c| game.node_key(c) }
            end
            cash = csar.cash

            tile = game.tiles.find { |t| t.name == '35' }
            process('lay_tile', csar, hex: 'M32', tile: tile.id, rotation: 3)
            expect(m32.tile.cities[1].tokened_by?(csar)).to be(true)
            expect(csar.cash).to eq(cash)
            expect(game.log.map(&:message).grep(/Connection Bonus/)).to be_empty
          end
        end

        %w[COR CNR CSAR NZA].each do |id|
          context "with #{id} at home on a pre-printed double City without a train" do
            let(:game) { Engine::Game::G18Africa::Game.new(players, id: seed_with(id)) }
            let(:corporation) { game.corporation_by_id(id) }

            it 'offers the home hex for #10 in its first Operating Round' do
              reach_first_stock_round
              start_with_director(corporation, funds: 0)
              finish_first_stock_round
              process('pass', current) until current == corporation

              hex = game.hex_by_id(corporation.coordinates)
              expect(corporation.trains).to be_empty
              expect(step.available_hex(corporation, hex)).to be_truthy
              expect(step.upgradeable_tiles(corporation, hex).map(&:name)).to include('10')
            end
          end
        end

        describe 'Town to City upgrades' do
          let(:game) { Engine::Game::G18Africa::Game.new(players, id: 1) }

          it 'allows yellow single Town tiles to become green City tiles' do
            town = game.tiles.find { |t| t.name == '58' }
            city = game.tiles.find { |t| t.name == '12' }
            double_town = game.tiles.find { |t| t.name == '1' }
            expect(game.yellow_town_to_city_upgrade?(town, city)).to be(true)
            expect(game.upgrades_to?(town, city)).to be(true)
            expect(game.yellow_town_to_city_upgrade?(double_town, city)).to be(false)
          end
        end
      end
    end
  end
end
