# frozen_string_literal: true

require 'spec_helper'
require_relative 'spec_helpers'

module Engine
  module Game
    module G18Africa
      describe Game do
        include G18AfricaSpecHelpers

        let(:players) { %w[a b c] }
        let(:game) { Engine::Game::G18Africa::Game.new(players, id: seed_with('MF', 'CSAR')) }
        let(:mf) { game.corporation_by_id('MF') }

        def give_private(sym, owner)
          company = game.company_by_id(sym)
          game.remove_card(company)
          company.owner = owner
          owner.companies << company
          company
        end

        def start_mf_and_operate
          reach_first_stock_round
          start_with_director(mf)
          finish_first_stock_round
          process('pass', current) until current == mf
        end

        describe 'Allen Rock Aggregates' do
          it 'allows a fifth yellow tile once' do
            start_mf_and_operate
            give_private('P2', mf.owner)
            lay(mf, 'D5', '115', [0])
            lay(mf, 'D7', '9', [3, 0])
            lay(mf, 'D9', '9', [3, 0])
            lay(mf, 'D11', '9', [3, 0])
            expect(step).to be_a(G18Africa::Step::Track)

            lay(mf, 'D13', '9', [3, 0])
            expect(step).not_to be_a(G18Africa::Step::Track)
            expect(game.used_private_ability?('P2')).to be(true)
          end
        end

        describe 'Thompson Wagon Works' do
          it 'allows a second upgrade of the same tile once' do
            start_mf_and_operate
            lay(mf, 'D5', '115', [0])
            process('pass', mf) until step.is_a?(G18Africa::Step::BuyTrain)
            train = game.depot.depot_trains.first
            process('buy_train', mf, train: train.id, price: train.price)
            advance until current == mf && game.operating_round_number == 2

            give_private('P3', mf)
            lay(mf, 'D5', '12', [5, 0, 1])
            expect(step).to be_a(G18Africa::Step::Track)
            expect(step.available_hex(mf, game.hex_by_id('D7'))).to be_nil

            lay(mf, 'D5', '38', [5, 0, 1])
            expect(game.hex_by_id('D5').tile.name).to eq('38')
            expect(game.used_private_ability?('P3')).to be(true)
          end
        end

        describe 'Jamieson Tropical Timber' do
          it 'waives one river cost once switched on' do
            start_mf_and_operate
            give_private('P4', mf.owner)
            expect(step.actions(mf)).to include('choose')
            process('choose', mf, choice: 'free_river')

            river = game.hex_by_id('G12')
            expect(game.upgrade_cost(river.tile, river, mf, mf)).to eq(0)
            expect(game.used_private_ability?('P4')).to be(true)
            expect(game.upgrade_cost(river.tile, river, mf, mf)).to eq(30)
          end
        end

        describe 'George Edmunds Colonial Factors' do
          it 'makes a token free and offers the most expensive one' do
            csar = game.corporation_by_id('CSAR')
            start_mf_and_operate
            token_step = game.round.steps.find { |s| s.is_a?(G18Africa::Step::Token) }
            csar.tokens.first.used = true

            expect(token_step.available_tokens(csar).map(&:price)).to eq([40])
            game.round.free_token = true
            expect(token_step.available_tokens(csar).map(&:price)).to eq([100])
          end
        end

        describe 'Madianos Olive Groves' do
          it 'lets its owner take the Priority Deal at the start of a Stock Round' do
            reach_first_stock_round
            owner = game.players.last
            give_private('P6', owner)
            finish_first_stock_round
            process('pass', current) while game.round.is_a?(Engine::Round::Operating)
            play_concession_auction

            expect(game.round).to be_a(Engine::Round::Choices)
            process('choose', owner, choice: 'take')
            expect(game.round).to be_a(Engine::Round::Stock)
            expect(game.players.first).to eq(owner)
            expect(game.used_private_ability?('P6')).to be(true)
          end

          it 'cannot be used by a Company' do
            reach_first_stock_round
            give_private('P6', mf)
            expect(game.private_usable?(mf, 'P6')).to be(false)
          end
        end
      end
    end
  end
end
