// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity =0.8.20;

interface IPriceOracleAggregator {
    function updateAsset(address asset, address oracle) external;

    function viewPriceInUSD(
        address token
    ) external view returns (uint256 price);
}
