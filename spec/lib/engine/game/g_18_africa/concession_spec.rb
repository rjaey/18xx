# frozen_string_literal: true

require 'spec_helper'
require_relative 'spec_helpers'

module Engine
  module Game
    module G18Africa
      describe Game do
        include G18AfricaSpecHelpers

        let(:players) { %w[a b c] }
        let(:game) { Engine::Game::G18Africa::Game.new(players, id: seed_with('MF')) }
        let(:mf) { game.corporation_by_id('MF') }

        def concession(id)
          game.companies.find { |c| c.id == "C_#{id}" }
        end

        def reach_concession_auction
          reach_first_stock_round
          process('pass', current) while game.round.is_a?(Engine::Round::Stock)
          process('pass', current) while game.round.is_a?(Engine::Round::Operating)
        end

        it 'marks every Commodity location on the map with a sticky icon' do
          G18Africa::Map::CONCESSIONS.each do |id, data|
            icon = game.hex_by_id(data[:commodity]).tile.icons.find { |i| i.name == id.downcase }
            expect(icon).not_to be_nil
            expect(icon.sticky).to be(true)
          end
        end

        it 'marks every destination port with a sticky plaque of the bonus' do
          G18Africa::Map::CONCESSIONS.each do |id, data|
            data[:ports].each do |port|
              icon = game.hex_by_id(port).tile.icons.find { |i| i.name == "#{id.downcase}-#{data[:bonus]}" }
              expect(icon).not_to be_nil, "no plaque on #{port} for #{id}"
              expect(icon.sticky).to be(true)
            end
          end
        end

        describe 'Concession Auction' do
          before { reach_concession_auction }

          it 'follows the first set of Operating Rounds and is opened by the Priority Deal holder' do
            expect(game.round).to be_a(G18Africa::Round::ConcessionAuction)
            expect(current).to eq(game.players.first)
            expect(step.actions(current)).to eq(%w[bid])
          end

          it 'lets the highest bidder choose a Concession and pay the bid' do
            opener = current
            others = game.players - [opener]
            process('bid', opener, company: game.concession_right.id, price: 0)
            process('bid', others.first, company: game.concession_right.id, price: 25)
            process('pass', others.last)
            process('pass', opener)

            winner = others.first
            expect(current).to eq(winner)
            process('choose', winner, choice: 'C_GOLD')

            expect(winner.companies).to include(concession('GOLD'))
            expect(winner.cash).to eq(game.players.find { |p| p == opener }.cash - 25)
            # the next auction starts to the left of the winner
            expect(current).to eq(game.players[(game.players.index(winner) + 1) % game.players.size])
          end

          it 'auctions all but one Concession, which is removed, then continues with the Stock Round' do
            priority = game.players.first
            play_concession_auction

            owned = game.players.flat_map(&:companies).select { |c| c.type == :concession }
            expect(owned.size).to eq(6)
            expect(game.companies.count { |c| c.type == :concession && c.closed? }).to eq(1)
            expect(game.round).to be_a(Engine::Round::Stock)
            expect(game.stock_round_number).to eq(2)
            expect(game.players.first).to eq(priority)
          end

          it 'does not count unassigned Concessions against the certificate limit' do
            player = game.players.first
            expect { play_concession_auction }.not_to(change { game.num_certs(player) })
          end
        end

        describe 'assigning and using a Concession' do
          before do
            reach_first_stock_round
            start_with_director(mf)
          end

          it 'requires a train reaching the Commodity and a port' do
            expect(game.can_run_concession?(mf, concession('MINERALS'))).to be(false)
          end

          it 'moves the Concession to the Company' do
            player = mf.owner
            game.award_concession(player, concession('MINERALS'))
            game.assign_concession(mf, concession('MINERALS'))

            expect(mf.companies).to include(concession('MINERALS'))
            expect(player.companies).not_to include(concession('MINERALS'))
          end

          it 'adds the bonus to a route including the Commodity and a port, without multiplier' do
            game.award_concession(mf.owner, concession('MINERALS'))
            game.assign_concession(mf, concession('MINERALS'))
            hexes = %w[G8 F7 E6 D5 D3].map { |id| game.hex_by_id(id) }
            route = double(all_hexes: hexes, train: double(owner: mf))
            expect(game.concession_bonus(route)).to eq(40)

            route = double(all_hexes: hexes.first(4), train: double(owner: mf))
            expect(game.concession_bonus(route)).to eq(0)
          end
        end
      end
    end
  end
end
