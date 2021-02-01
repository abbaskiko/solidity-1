pragma solidity >=0.0;
import "../Utils/Math.sol";
import "../MarketMakers/MarketMaker.sol";


/// @title LMSR market maker contract - Calculates share prices based on share distribution and initial funding
/// @author Alan Lu - <alan.lu@gnosis.pm>
contract LMSRMarketMaker is MarketMaker {
    using Math for *;

    /*
     *  Constants
     */
    uint256 constant ONE = 0x10000000000000000;
    int256 constant EXP_LIMIT = 2352680790717288641401;

    /*
     *  Public functions
     */
    /// @dev Returns cost to buy given number of outcome tokens
    /// @param market Market contract
    /// @param outcomeTokenIndex Index of outcome to buy
    /// @param outcomeTokenCount Number of outcome tokens to buy
    /// @return cost Cost
    function calcCost(Market market, uint8 outcomeTokenIndex, uint256 outcomeTokenCount)
        public
        override
        view
        returns (uint256 cost)
    {
        require(market.eventContract().getOutcomeCount() > 1);
        int256[] memory netOutcomeTokensSold = getNetOutcomeTokensSold(market);
        // Calculate cost level based on net outcome token balances
        int256 logN = Math.ln(uint256(netOutcomeTokensSold.length) * ONE);
        uint256 funding = market.funding();
        int256 costLevelBefore = calcCostLevel(logN, netOutcomeTokensSold, funding);
        // Add outcome token count to net outcome token balance
        require(int256(outcomeTokenCount) >= 0);
        netOutcomeTokensSold[outcomeTokenIndex] = netOutcomeTokensSold[outcomeTokenIndex].add(int256(outcomeTokenCount));
        // Calculate cost level after balance was updated
        int256 costLevelAfter = calcCostLevel(logN, netOutcomeTokensSold, funding);
        // Calculate cost as cost level difference
        require(costLevelAfter >= costLevelBefore);
        cost = uint256(costLevelAfter - costLevelBefore);
        // Take the ceiling to account for rounding
        if (cost / ONE * ONE == cost)
            cost /= ONE;
        else
            // Integer division by ONE ensures there is room to (+ 1)
            cost = cost / ONE + 1;
        // Make sure cost is not bigger than 1 per share
        if (cost > outcomeTokenCount)
            cost = outcomeTokenCount;
    }

    /// @dev Returns profit for selling given number of outcome tokens
    /// @param market Market contract
    /// @param outcomeTokenIndex Index of outcome to sell
    /// @param outcomeTokenCount Number of outcome tokens to sell
    /// @return profit Profit
    function calcProfit(Market market, uint8 outcomeTokenIndex, uint256 outcomeTokenCount)
        public
        override
        view
        returns (uint256 profit)
    {
        require(market.eventContract().getOutcomeCount() > 1);
        int256[] memory netOutcomeTokensSold = getNetOutcomeTokensSold(market);
        // Calculate cost level based on net outcome token balances
        int256 logN = Math.ln(uint256(netOutcomeTokensSold.length) * ONE);
        uint256 funding = market.funding();
        int256 costLevelBefore = calcCostLevel(logN, netOutcomeTokensSold, funding);
        // Subtract outcome token count from the net outcome token balance
        require(int256(outcomeTokenCount) >= 0);
        netOutcomeTokensSold[outcomeTokenIndex] = netOutcomeTokensSold[outcomeTokenIndex].sub(int256(outcomeTokenCount));
        // Calculate cost level after balance was updated
        int256 costLevelAfter = calcCostLevel(logN, netOutcomeTokensSold, funding);
        // Calculate profit as cost level difference
        require(costLevelBefore >= costLevelAfter);
        // Take the floor
        profit = uint256(costLevelBefore - costLevelAfter) / ONE;
    }

    /// @dev Returns marginal price of an outcome
    /// @param market Market contract
    /// @param outcomeTokenIndex Index of outcome to determine marginal price of
    /// @return price Marginal price of an outcome as a fixed point number
    function calcMarginalPrice(Market market, uint8 outcomeTokenIndex)
        public
        override
        view
        returns (uint256 price)
    {
        require(market.eventContract().getOutcomeCount() > 1);
        int256[] memory netOutcomeTokensSold = getNetOutcomeTokensSold(market);
        int256 logN = Math.ln(uint256(netOutcomeTokensSold.length) * ONE);
        uint256 funding = market.funding();
        // The price function is exp(quantities[i]/b) / sum(exp(q/b) for q in quantities)
        // To avoid overflow, calculate with
        // exp(quantities[i]/b - offset) / sum(exp(q/b - offset) for q in quantities)
        (uint256 sum, , uint256 outcomeExpTerm) = sumExpOffset(logN, netOutcomeTokensSold, funding, outcomeTokenIndex);
        return outcomeExpTerm / (sum / ONE);
    }

    /*
     *  Private functions
     */
    /// @dev Calculates the result of the LMSR cost function which is used to
    ///      derive prices from the market state
    /// @param logN Logarithm of the number of outcomes
    /// @param netOutcomeTokensSold Net outcome tokens sold by market
    /// @param funding Initial funding for market
    /// @return costLevel Cost level
    function calcCostLevel(int256 logN, int256[] memory netOutcomeTokensSold, uint256 funding)
        private
        view
        returns(int256 costLevel)
    {
        // The cost function is C = b * log(sum(exp(q/b) for q in quantities)).
        // To avoid overflow, we need to calc with an exponent offset:
        // C = b * (offset + log(sum(exp(q/b - offset) for q in quantities)))
        (uint256 sum, int256 offset, ) = sumExpOffset(logN, netOutcomeTokensSold, funding, 0);
        costLevel = Math.ln(sum);
        costLevel = costLevel.add(offset);
        costLevel = (costLevel.mul(int256(ONE)) / logN).mul(int256(funding));
    }

    /// @dev Calculates sum(exp(q/b - offset) for q in quantities), where offset is set
    ///      so that the sum fits in 248-256 bits
    /// @param logN Logarithm of the number of outcomes
    /// @param netOutcomeTokensSold Net outcome tokens sold by market
    /// @param funding Initial funding for market
    /// @param outcomeIndex Index of exponential term to extract (for use by marginal price function)
    /// @return sum The sum of the outcomes
    /// @return offset The offset that is used for all
    /// @return outcomeExpTerm The summand associated with the supplied index
    function sumExpOffset(int256 logN, int256[] memory netOutcomeTokensSold, uint256 funding, uint8 outcomeIndex)
        private
        view
        returns (uint256 sum, int256 offset, uint256 outcomeExpTerm)
    {
        // Naive calculation of this causes an overflow
        // since anything above a bit over 133*ONE supplied to exp will explode
        // as exp(133) just about fits into 192 bits of whole number data.

        // The choice of this offset is subject to another limit:
        // computing the inner sum successfully.
        // Since the index is 8 bits, there has to be 8 bits of headroom for
        // each summand, meaning q/b - offset <= exponential_limit,
        // where that limit can be found with `mp.floor(mp.log((2**248 - 1) / ONE) * ONE)`
        // That is what EXP_LIMIT is set to: it is about 127.5

        // finally, if the distribution looks like [BIG, tiny, tiny...], using a
        // BIG offset will cause the tiny quantities to go really negative
        // causing the associated exponentials to vanish.

        int256 maxQuantity = Math.max(netOutcomeTokensSold);
        require(logN >= 0 && int256(funding) >= 0);
        offset = maxQuantity.mul(logN) / int256(funding);
        offset = offset.sub(EXP_LIMIT);
        uint256 term;
        for (uint8 i = 0; i < netOutcomeTokensSold.length; i++) {
            term = Math.exp((netOutcomeTokensSold[i].mul(logN) / int256(funding)).sub(offset));
            if (i == outcomeIndex)
                outcomeExpTerm = term;
            sum = sum.add(term);
        }
    }

    /// @dev Gets net outcome tokens sold by market. Since all sets of outcome tokens are backed by
    ///      corresponding collateral tokens, the net quantity of a token sold by the market is the
    ///      number of collateral tokens (which is the same as the number of outcome tokens the
    ///      market created) subtracted by the quantity of that token held by the market.
    /// @param market Market contract
    /// @return quantities Net outcome tokens sold by market
    function getNetOutcomeTokensSold(Market market)
        private
        view
        returns (int256[] memory quantities)
    {
        quantities = new int256[](market.eventContract().getOutcomeCount());
        for (uint8 i = 0; i < quantities.length; i++)
            quantities[i] = market.netOutcomeTokensSold(i);
    }
}
