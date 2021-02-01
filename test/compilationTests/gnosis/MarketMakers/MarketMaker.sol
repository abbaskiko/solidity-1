pragma solidity >=0.0;
import "../Markets/Market.sol";


/// @title Abstract market maker contract - Functions to be implemented by market maker contracts
abstract contract MarketMaker {

    /*
     *  Public functions
     */
    function calcCost(Market market, uint8 outcomeTokenIndex, uint256 outcomeTokenCount) virtual public view returns (uint256);
    function calcProfit(Market market, uint8 outcomeTokenIndex, uint256 outcomeTokenCount) virtual public view returns (uint256);
    function calcMarginalPrice(Market market, uint8 outcomeTokenIndex) virtual public view returns (uint256);
}
