// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity =0.8.20;

import "../interface/IPriceOracleAggregator.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/lib/contracts/libraries/FixedPoint.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol";
import "@uniswap/v2-periphery/contracts/libraries/UniswapV2OracleLibrary.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract PriceOracleAggregator is Ownable {
    using FixedPoint for *;

    uint public PERIOD = 1 hours;
    IUniswapV2Pair public immutable pair;
    bool public isFirstToken;
    address public immutable token0;
    address public immutable token1;

    uint public price0CumulativeLast;
    uint public price1CumulativeLast;
    uint32 public blockTimestampLast;

    FixedPoint.uq112x112 public price0Average;
    FixedPoint.uq112x112 public price1Average;

    constructor(
        address _factory,
        address _tokenA,
        address _tokenB
    ) Ownable(msg.sender) {
        require(_factory != address(0), "UNIV2: Invalid factory");
        require(_tokenA != address(0), "UNIV2: Invalid tokenA");
        require(_tokenB != address(0), "UNIV2: Invalid tokenB");

        IUniswapV2Pair _pair = IUniswapV2Pair(
            UniswapV2Library.pairFor(_factory, _tokenA, _tokenB)
        );
        require(address(_pair) != address(0), "UNIV2: Invalid Pair");

        pair = _pair;
        token0 = _pair.token0();
        token1 = _pair.token1();

        price0CumulativeLast = _pair.price0CumulativeLast(); // fetch the current accumulated price value (1 / 0)
        price1CumulativeLast = _pair.price1CumulativeLast(); // fetch the current accumulated price value (0 / 1)
        uint112 reserve0;
        uint112 reserve1;
        (reserve0, reserve1, blockTimestampLast) = _pair.getReserves();
        require(reserve0 != 0 && reserve1 != 0, "UNIV2: NO_RESERVES"); // ensure that there's liquidity in the pair

        if (_tokenA == _pair.token0()) {
            isFirstToken = true;
        } else {
            isFirstToken = false;
        }
    }

    function canUpdate() public view returns (bool) {
        uint32 blockTimestamp = UniswapV2OracleLibrary.currentBlockTimestamp();
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // Overflow is desired
        return (timeElapsed >= PERIOD);
    }

    function update() external {
        (
            uint256 price0Cumulative,
            uint256 price1Cumulative,
            uint32 blockTimestamp
        ) = UniswapV2OracleLibrary.currentCumulativePrices(address(pair));

        // overflow is desired
        uint256 timeElapsed = blockTimestamp > blockTimestampLast
            ? blockTimestamp - blockTimestampLast
            : uint256(blockTimestamp) + 2 ** 32 - uint256(blockTimestampLast);

        // Ensure that at least one full period has passed since the last update
        require(timeElapsed >= PERIOD, "UniswapPairOracle: PERIOD_NOT_ELAPSED");

        // Overflow is desired, casting never truncates
        // Cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
        price0Average = FixedPoint.uq112x112(
            uint224((price0Cumulative - price0CumulativeLast) / timeElapsed)
        );
        price1Average = FixedPoint.uq112x112(
            uint224((price1Cumulative - price1CumulativeLast) / timeElapsed)
        );

        price0CumulativeLast = price0Cumulative;
        price1CumulativeLast = price1Cumulative;
        blockTimestampLast = blockTimestamp;
    }

    function priceShow() public view returns (uint price) {
        if (isFirstToken) {
            price =
                price0Average
                    .mul(10 ** (IERC20Metadata(token0).decimals()))
                    .decode144() /
                (10 ** IERC20Metadata(token1).decimals());
        } else {
            price =
                price1Average
                    .mul(10 ** (IERC20Metadata(token1).decimals() + 8))
                    .decode144() /
                (10 ** IERC20Metadata(token0).decimals());
        }
    }
}
