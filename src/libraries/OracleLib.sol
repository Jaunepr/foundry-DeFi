// SPDX-License-Identifier: MIT

// check the price feed works normally, 3600s update once
pragma solidity ^0.8.23;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @author Jaunepr
 * @notice This library is used to check the Chainlink Oracle for stale data.
 * If a price is stale, the function will revert, and render the DSCEngine unusable - this is by designed
 *
 * We want the DSCEngine to freeze if price is stale
 *
 * So if the Chainlink network explodes and you have a lot of money locked in the protocol...
 */
library OracleLib {
    error OracleLib__StalePrice();

    uint256 private constant TIMEOUT = 1 hours; // 1*60*60 seconds

    function checkStaleLatestRoundData(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();

        uint256 duration = block.timestamp - updatedAt;
        if (duration > TIMEOUT) {
            revert OracleLib__StalePrice();
        }
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
