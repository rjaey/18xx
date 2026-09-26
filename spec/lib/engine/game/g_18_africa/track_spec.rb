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

          it 'does not let a Company without a train upgrade a City' do
            lay(mf, 'D5', '115', [0])
            process('pass', mf) while game.round.current_entity == mf
            process('pass', current) until current == mf
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

          it 'reserves the hex, not a particular City' do
            start_with_director(csar)
            other = (game.corporations - [csar, nza]).first
            city = m32.tile.cities.find { |c| c.tokens.compact.empty? }

            expect(m32.tile.cities.flat_map(&:reservations).compact).to be_empty
            expect(m32.tile.reservations).to eq([nza])
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
