// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity =0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interface/IBFnft.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interface/IPriceOracleAggregator.sol";

/**
 * @title BondingFarmPool contract
 * @notice you can lockFarm and bonding
 *  #LockFarm 
 *      -LockFarm is a kind of staking contract but it provides the locking period
 *        So as long as the tokens are locked, more reward will be made.
 *  #Bonding
 *      -Bonding is a mechanism to sell tokens in discount for X period locking
        -BondV2 is an upgrade of the bonding but it provides the staking reward as an         incentive one.The bonded tokens are being staked in to the above LockFarm and can make rewards until the bonding finished.
 *  #Oracle    
 *      -Oracle aggregator is to return any tokens price in USD by using Uniswap TWAP oracle 
 * @dev Main point of bonding and lockfarm
 * - Users can:
 *   #bond 
 *   #deposit 
 *   #withdraw 
 *   #claim
 *   #claimAll
 * @author John
 */

contract BondingFarmPool is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardToken;

    uint public totalReward;
    uint public totalTokenAmount;
    uint public totalTokenBoostedAmount;
    uint public accTokenPerShare;
    uint public rewardRate = 1e10;
    uint public rewardCycle = 7 days;
    uint public lastUpdatedTime;

    uint public lockedMaxMultiplier = 3e6; //3X for 3 years
    uint public lockedMaxTime = 3 * 365 days;
    uint public lockedMinTime = 30 days;
    IBFnft public bfnft;
    IPriceOracleAggregator public oracle;

    struct stakeInfo {
        uint id;
        uint amount;
        uint boostedAmount;
        uint endTime;
        uint rewardDebt;
        uint pendingReward;
        address owner;
    }

    struct discountMode {
        uint discount; // e.g 30000(3%)
        uint locktime;
    }

    mapping(address => uint) public remainingRewards;

    mapping(uint => stakeInfo) public stakeLists;

    uint private constant MULTIPLIER_BASE = 1e6; //1X for 1 month
    uint private constant PRICE_PRECISION = 1e6;
    uint private constant REWARD_MULTIPLIER = 1e12;

    discountMode[] public mode;
    address[] public assetMode;

    event Stake(address staker, uint stakeId, uint amount, uint period);
    event Withdraw(address receiver, uint stakeId, uint amount);
    event Claim(address to, uint stakeId, uint amount);

    constructor(
        address _bfnft,
        address _stakingToken,
        address _rewardToken,
        address _oracle
    ) Ownable(msg.sender) {
        require(_stakingToken != address(0), "Invalid token");
        require(_rewardToken != address(0), "Invalid token");
        bfnft = IBFnft(_bfnft);

        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);

        oracle = IPriceOracleAggregator(_oracle);
    }

    /**
     * @dev Deposit an 'amount' of staking token into the staking pool
     * @param amount the amount that staker staked into the staking pool
     * @param secs  lock period
     */

    function deposit(uint amount, uint secs) external nonReentrant {
        require(amount > 0, "Invalid amount");
        require(secs >= lockedMinTime && secs <= lockedMaxTime, "Invalid secs");

        _stake(msg.sender, amount, secs, false);
    }

    /**
     * @dev sell the bondingToken in discount for its mode and stake it into the staking Pool
     * @param _assetMode principal asset setting
     * @param _amount the bonding token amount that user sell
     * @param _mode discount mode setting
     */
    function bond(
        uint _assetMode,
        uint _amount,
        uint _mode
    ) external nonReentrant {
        require(_mode < mode.length, "Invalid mode");
        require(_assetMode < assetMode.length, "Invalid asset mode");
        require(_amount > 0, "Invalid amount");

        uint totalBalance = stakingToken.balanceOf(address(this));
        require(_amount <= totalBalance, "amounts are too much");

        address asset = assetMode[_assetMode];
        uint secs = mode[_mode].locktime;
        uint discount = mode[_mode].discount;
        uint price = oracle.viewPriceInUSD(address(stakingToken));

        //get the discount price
        uint needAssets = (price *
            _amount *
            (10 ** IERC20Metadata(asset).decimals()) *
            (PRICE_PRECISION - discount)) /
            (PRICE_PRECISION *
                (10 ** IERC20Metadata(address(stakingToken)).decimals()));

        require(
            IERC20(asset).balanceOf(msg.sender) >= needAssets,
            "your assets are not enough"
        );

        IERC20(asset).safeTransferFrom(msg.sender, address(this), needAssets);
        _stake(msg.sender, _amount, secs, true);
    }

    /**
     * @dev return the necessary amount for bonding and possibility
     * @param _assetMode principal asset setting
     * @param _amount the bonding token amount that user sell
     * @param _mode discount mode setting
     * @return possible  return the possibility
     * @return needAssets return the necessary amount for bonding
     */
    function getAmountsIn(
        uint _assetMode,
        uint _amount,
        uint _mode
    ) external view returns (bool possible, uint needAssets) {
        require(_mode < mode.length, "Invalid mode");
        require(_assetMode < assetMode.length, "Invalid asset mode");

        address asset = assetMode[_assetMode];
        uint discount = mode[_mode].discount;
        uint price = oracle.viewPriceInUSD(address(stakingToken));

        //get the discount price
        needAssets =
            (price *
                _amount *
                (10 ** IERC20Metadata(asset).decimals()) *
                (PRICE_PRECISION - discount)) /
            (PRICE_PRECISION *
                (10 ** IERC20Metadata(address(stakingToken)).decimals()));

        possible = IERC20(asset).balanceOf(msg.sender) >= needAssets;
    }

    /**
     * @dev withdraw the staked amount and reward
     * @param stakeId the Id of stake info
     */
    function withdraw(uint stakeId) external nonReentrant {
        require(stakeLists[stakeId].owner == msg.sender, "Invalid owner");
        require(stakeLists[stakeId].endTime <= block.timestamp, "still locked");

        updateFarm();

        //burn the stakeId from user
        bfnft.burn(stakeId);

        stakeInfo storage info = stakeLists[stakeId];

        totalTokenAmount -= info.amount;
        totalTokenBoostedAmount -= info.boostedAmount;

        //distribute the reward
        rewardDistribution(msg.sender, stakeId);

        //amount of user remaining
        remainingRewards[msg.sender] += info.pendingReward;

        delete stakeLists[stakeId];

        emit Withdraw(msg.sender, stakeId, info.amount);
    }

    /**
     * @dev claim the reward for stakeId
     * @param stakeId the Id of stake info
     */
    function claim(uint stakeId) external nonReentrant {
        require(stakeLists[stakeId].owner == msg.sender, "Invalid owner");

        updateFarm();

        rewardDistribution(msg.sender, stakeId);
    }

    /**
     * @dev claim the remaining rewards
     */
    function claimRemaining() external nonReentrant {
        uint amount = remainingRewards[msg.sender];
        require(amount > 0, "no remaining rewards");

        remainingRewards[msg.sender] -= rewardTransfer(msg.sender, amount);
    }

    /**
     * @dev claim the user's all rewards.
     */
    function claimAll() external nonReentrant {
        updateFarm();

        //user's total stake count
        uint balance = bfnft.balanceOf(msg.sender);

        for (uint i = 0; i < balance; i++) {
            uint stakeId = bfnft.tokenOfOwnerByIndex(msg.sender, i);
            rewardDistribution(msg.sender, stakeId);
        }
    }

    /**
     * @dev rewards are distributed to user
     * @param to the address of user that get rewards
     * @param stakeId the Id of stake info
     */
    function rewardDistribution(address to, uint stakeId) internal {
        stakeInfo storage info = stakeLists[stakeId];

        uint pending = (info.boostedAmount * accTokenPerShare) /
            REWARD_MULTIPLIER -
            info.rewardDebt;

        if (pending > 0) {
            info.pendingReward += pending;

            uint distibutedAmount = rewardTransfer(to, info.pendingReward);
            emit Claim(to, stakeId, distibutedAmount);

            info.pendingReward -= distibutedAmount;
        }

        info.rewardDebt =
            (info.boostedAmount * accTokenPerShare) /
            REWARD_MULTIPLIER;
    }

    /**
     * @dev transfer the rewards to user
     * @param to the address of user that get the rewards
     * @param amount the 'amount' of the rewards
     */
    function rewardTransfer(address to, uint amount) internal returns (uint) {
        uint totalBalance = IERC20(rewardToken).balanceOf(address(this));

        if (totalBalance == 0) {
            return 0;
        }

        if (amount > totalBalance) {
            IERC20(rewardToken).safeTransfer(to, totalBalance);
            return totalBalance;
        } else {
            IERC20(rewardToken).safeTransfer(to, amount);
            return amount;
        }
    }

    /**
     * @dev calculate the total Multiplier
     * @param period lockTime
     */
    function stakingMultiplier(
        uint period
    ) public view returns (uint multiplier) {
        multiplier =
            MULTIPLIER_BASE +
            (period * (lockedMaxMultiplier - MULTIPLIER_BASE)) /
            (lockedMaxTime - lockedMinTime);
        if (multiplier > lockedMaxMultiplier) multiplier = lockedMaxMultiplier;
    }

    /**
     * @dev update the stake states like accPerShareToken, lasteUpdatedTime
     */
    function updateFarm() internal {
        if (totalTokenBoostedAmount == 0) {
            return;
        }

        uint multiplier = block.timestamp - lastUpdatedTime;
        uint rewards = (rewardRate * multiplier) / rewardCycle;

        accTokenPerShare +=
            (rewards * REWARD_MULTIPLIER) /
            totalTokenBoostedAmount;
        lastUpdatedTime = block.timestamp;
    }

    /**
     * @dev stake the staking Token to the pool with lockTime
     * @param staker the address of staker
     * @param amount the 'amount' of the staking Token
     * @param secs the lockTime
     */
    function _stake(
        address staker,
        uint amount,
        uint secs,
        bool bonding
    ) internal {
        if (!bonding) {
            stakingToken.safeTransferFrom(staker, address(this), amount);
        }

        //update the states
        updateFarm();

        uint multiplier = stakingMultiplier(secs);
        uint boostedAmount = (amount * multiplier) / PRICE_PRECISION;

        totalTokenAmount += amount;
        totalTokenBoostedAmount += boostedAmount;

        //mint the stakeId to use using nft
        uint stakeId = bfnft.mint(staker);

        stakeInfo storage info = stakeLists[stakeId];
        info.id = stakeId;
        info.amount = amount;
        info.boostedAmount = boostedAmount;
        info.endTime = block.timestamp + secs;
        info.rewardDebt =
            (boostedAmount * accTokenPerShare) /
            REWARD_MULTIPLIER;
        info.pendingReward = 0;
        info.owner = staker;

        emit Stake(staker, stakeId, amount, secs);
    }

    /**
     * @dev set the discount mode
     * @param index the index of mode set
     * @param _mode mode format like lockTime, discount percentage
     */
    function setMode(uint index, discountMode calldata _mode) public onlyOwner {
        if (index >= mode.length) {
            mode.push(_mode);
        } else {
            mode[index] = _mode;
        }
    }

    /**
     * @dev delete the existing discount mode
     * @param index the index of discount mode deleted
     */
    function deleteMode(uint index) public onlyOwner {
        require(index < mode.length, "Invalid index");
        require(mode.length != 1, "not allowed");

        uint length = mode.length;
        mode[index] = mode[length - 1];
        mode.pop();
    }

    /**
     * @dev set the discount mode
     * @param index the index of asset mode set
     * @param _asset the address of principal stablecoin added
     */
    function setAsset(uint index, address _asset) public onlyOwner {
        if (index >= assetMode.length) {
            assetMode.push(_asset);
        } else {
            assetMode[index] = _asset;
        }
    }

    /**
     * @dev delete the existing principal stable coin address
     * @param index the index of stable coin deleted
     */
    function deleteAsset(uint index) public onlyOwner {
        require(index < assetMode.length, "Invalid index");
        require(assetMode.length != 1, "not allowed");

        uint length = assetMode.length;
        assetMode[index] = assetMode[length - 1];
        assetMode.pop();
    }
}
