# frozen_string_literal: true

require_relative '../../../step/dividend'

module Engine
  module Game
    module G18Africa
      module Step
        class Dividend < Engine::Step::Dividend
          # Shares in the Bank Pool, Bank Deck, Bank Discard and players' hands do not pay [3.5.2]
          def corporation_dividends(_entity, _per_share)
            0
          end

          # Withholding or no revenue: back one space [3.5.1].
          # Paying out: revenue relative to the Market Value moves the marker up to four spaces [3.5.2]
          def share_price_change(entity, revenue)
            return { share_direction: :left, share_times: 1 } unless revenue.positive?

            value = entity.share_price.price
            times =
              if revenue >= 4 * value then 4
              elsif revenue >= 3 * value then 3
              elsif revenue >= 2 * value then 2
              elsif revenue * 2 >= value then 1
              else
                0
              end
            times.zero? ? {} : { share_direction: :right, share_times: times }
          end
        end
      end
    end
  end
end
