// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity =0.8.20;

import "../interface/IPriceOracleAggregator.sol";
import "../interface/IOracle.sol";

contract MockOracle is IPriceOracleAggregator {
    mapping(address => IOracle) public priceOracle;

    mapping(address => uint) public price;

    constructor(address _token, uint _price) {
        price[_token] = _price;
    }

    function updateAsset(address _token, address _oracle) external override {
        priceOracle[_token] = IOracle(_oracle);
    }

    function viewPriceInUSD(
        address _token
    ) external view override returns (uint256) {
        return price[_token];
    }
}
