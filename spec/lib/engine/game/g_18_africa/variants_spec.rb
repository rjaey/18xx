# frozen_string_literal: true

require 'spec_helper'
require_relative 'spec_helpers'

module Engine
  module Game
    module G18Africa
      describe Game do
        include G18AfricaSpecHelpers

        def new_game(players, rules)
          Engine::Game::G18Africa::Game.new(players, id: 7, optional_rules: rules)
        end

        describe 'Simpson variant' do
          let(:game) { new_game(%w[a b c], [:simpson]) }

          it "deals every player a Director's Certificate and a full hand" do
            expect(game.players.map { |p| p.hand.count { |c| c.type == :director } }).to all(be >= 1)
            expect(game.players.map { |p| p.hand.size }).to all(eq(14))
          end
        end

        describe 'two player auction variant' do
          let(:game) { new_game(%w[a b], [:two_player_auction]) }

          it 'swaps 8 discards for 8 Bank Deck cards before the auction' do
            deck_size = game.bank_deck.size
            game.players.size.times do
              process('select_multiple_companies', current, companies: current.hand.first(step.cards_to_keep).map(&:id))
            end

            expect(game.auction_cards.size).to eq(16)
            expect(game.bank_deck.size).to eq(deck_size)
            expect(game.log.to_a.map(&:message)).to include(a_string_including('8 discarded cards are shuffled back'))
          end
        end

        describe 'Concessions variant' do
          let(:game) { new_game(%w[a b c], [:concessions_penalty]) }
          let(:plain) { new_game(%w[a b c], []) }

          it 'deducts £100 per unassigned Concession at the end' do
            [game, plain].each do |g|
              concession = g.companies.find { |c| c.type == :concession }
              g.award_concession(g.players.first, concession)
            end
            expect(plain.player_value(plain.players.first) - game.player_value(game.players.first)).to eq(100)
          end
        end
      end
    end
  end
end
