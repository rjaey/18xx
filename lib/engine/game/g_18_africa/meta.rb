# frozen_string_literal: true

require_relative '../meta'

module Engine
  module Game
    module G18Africa
      module Meta
        include Game::Meta

        DEV_STAGE = :prealpha

        GAME_TITLE = '18Africa'
        GAME_DESIGNER = 'Jeff Edmunds'
        GAME_LOCATION = 'Africa'
        GAME_RULES_URL = 'https://boardgamegeek.com/filepage/302566/rules-v21'
        GAME_ISSUE_LABEL = '18Africa'

        PLAYER_RANGE = [2, 5].freeze

        # Official variants [10]
        OPTIONAL_RULES = [
          {
            sym: :two_player_auction,
            short_name: 'Two player auction variant',
            desc: 'The discards are shuffled, 8 of them go back into the Bank Deck and the top 8 '\
                  'Bank Deck cards are auctioned instead, so nobody knows exactly what the other discarded.',
            players: [2],
          },
          {
            sym: :simpson,
            short_name: 'Simpson variant',
            desc: "Every player is dealt one Director's Certificate before the other cards.",
          },
          {
            sym: :concessions_penalty,
            short_name: 'Concessions variant',
            desc: 'Each Concession bought in the auction but never assigned costs £100 at the end of the game.',
          },
        ].freeze
      end
    end
  end
end
