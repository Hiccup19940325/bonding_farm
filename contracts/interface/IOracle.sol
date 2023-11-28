// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity =0.8.20;

interface IOracle {
    function viewPriceInUSD() external view returns (uint256 price);
}
