import {
    time,
    loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address'
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers, network } from "hardhat";
import {
    PrincipalToken,
    StakingToken,
    RewardToken,
    MockOracle,
    BondingFarmPool,
    BFnft
} from '../typechain-types'

import {
    ether,
    gWei,
    wei,
    usdc,
    deployBFnft,
    deployBondingFarmPool,
    deployMockOracle,
    deployPrincipalToken,
    deployRewardToken,
    deployStakingToken
} from '../helper'

describe("BondingFarm", function () {
    let owner: SignerWithAddress;
    let alice: SignerWithAddress;
    let bob: SignerWithAddress;
    let john: SignerWithAddress;

    let principalToken: PrincipalToken;
    let stakingToken: StakingToken;
    let rewardToken: RewardToken;
    let mockOracle: MockOracle;
    let bondingFarmPool: BondingFarmPool;
    let bfnft: BFnft;
    let lockTime: bigint;

    before(async () => {
        const signers: SignerWithAddress[] = await ethers.getSigners();

        owner = signers[0];
        alice = signers[1];
        bob = signers[2];
        john = signers[3];

        stakingToken = await deployStakingToken();
        await stakingToken.mint(alice.address, ether(1000));
        await stakingToken.mint(bob.address, ether(1000));

        rewardToken = await deployRewardToken();

        principalToken = await deployPrincipalToken();
        await principalToken.mint(john.address, ether(1000));

        mockOracle = await deployMockOracle(stakingToken.getAddress(), 100);

        bfnft = await deployBFnft();

        bondingFarmPool = await deployBondingFarmPool(
            bfnft.getAddress(),
            stakingToken.getAddress(),
            rewardToken.getAddress(),
            mockOracle.getAddress(),
        );

        lockTime = BigInt(365 * 24 * 3600);

        await bondingFarmPool.setAsset(0, principalToken.getAddress());
        await bondingFarmPool.setMode(0, { discount: 30000, locktime: lockTime })

        await rewardToken.mint(bondingFarmPool.getAddress(), ether(1000));
        await stakingToken.mint(bondingFarmPool.getAddress(), ether(100));
    })

    describe('Bond', async () => {
        it('Failed-invalid mode', async () => {
            await expect(bondingFarmPool.connect(john).bond(1, ether(10), 1)).to.be.revertedWith('Invalid mode');
            await expect(bondingFarmPool.connect(john).getAmountsIn(1, ether(10), 1)).to.be.revertedWith('Invalid mode');
        });

        it('Failed-invalid asset mode', async () => {
            await expect(bondingFarmPool.connect(john).bond(1, ether(10), 0)).to.be.revertedWith('Invalid asset mode');
            await expect(bondingFarmPool.connect(john).getAmountsIn(1, ether(10), 0)).to.be.revertedWith('Invalid asset mode');
        });

        it('Failed-amounts are too much', async () => {
            await expect(bondingFarmPool.connect(john).bond(0, ether(10000), 0)).to.be.revertedWith('amounts are too much');
        });

        it('Failed-your assets are not enough', async () => {
            const amounts = await bondingFarmPool.connect(john).getAmountsIn(0, ether(100), 0);

            console.log("NeedAssets", amounts[1] / BigInt(1e18));

            await expect(bondingFarmPool.connect(john).bond(0, ether(100), 0)).to.be.revertedWith('your assets are not enough');
        });

        it('Success-bond 10 eth & lock 1 year', async () => {
            const bondAmount = await bondingFarmPool.connect(john).getAmountsIn(0, ether(10), 0);
            await principalToken.connect(john).approve(bondingFarmPool.getAddress(), bondAmount[1]);
            await bondingFarmPool.connect(john).bond(0, ether(10), 0);

            expect(await principalToken.balanceOf(john.address)).to.equal(ether(1000) - bondAmount[1]);
            expect(await principalToken.balanceOf(bondingFarmPool.getAddress())).to.equal(bondAmount[1]);
            expect(await stakingToken.balanceOf(bondingFarmPool.getAddress())).to.equal(ether(100));
        });

        it('NFT info-amount, owner, endTime', async () => {
            expect(await bfnft.balanceOf(john.address)).to.equal(1);
            const stake_Id = await bfnft.tokenOfOwnerByIndex(john.address, 0);

            const stake_info = await bondingFarmPool.stakeLists(stake_Id);
            expect(stake_info.amount).to.equal(ether(10));
            expect(stake_info.owner).to.equal(john.address);
            expect(stake_info.endTime).to.equal(BigInt(await time.latest()) + BigInt(lockTime));
        });
    })

    describe('Deposit', async () => {
        it('Failed-Invalid amount', async () => {
            await expect(bondingFarmPool.connect(john).deposit(0, 3600)).to.be.revertedWith('Invalid amount');
        })

        it('Failed-Invalid secs', async () => {
            await expect(bondingFarmPool.connect(john).deposit(ether(1), 3600)).to.be.revertedWith('Invalid secs');
        })

        it('Success - confirm balance', async () => {
            await stakingToken.connect(bob).approve(bondingFarmPool.getAddress(), ether(10));
            await bondingFarmPool.connect(bob).deposit(ether(10), lockTime);

            expect(await stakingToken.balanceOf(bob.address)).to.equal(ether(990));
            expect(await stakingToken.balanceOf(bondingFarmPool.getAddress())).to.equal(ether(110));
        })

        it('NFT info-amount, owner, endTime', async () => {
            expect(await bfnft.balanceOf(bob.address)).to.equal(1);
            const stake_Id = await bfnft.tokenOfOwnerByIndex(bob.address, 0);

            const stake_info = await bondingFarmPool.stakeLists(stake_Id);
            expect(stake_info.amount).to.equal(ether(10));
            expect(stake_info.owner).to.equal(bob.address);
            expect(stake_info.endTime).to.equal(BigInt(await time.latest()) + BigInt(lockTime));
        });
    })

    describe('Claim', async () => {
        it('Failed-Invalid owner', async () => {
            await expect(bondingFarmPool.connect(bob).claim(0)).to.be.revertedWith("Invalid owner");
        })

        it('Success-ClaimRewards is grown over the time', async () => {
            await bondingFarmPool.connect(bob).claim(1);
            const balance0 = await rewardToken.balanceOf(bob.address);

            await time.increase(3600 * 24 * 100);
            await bondingFarmPool.connect(bob).claim(1);
            const balance1 = await rewardToken.balanceOf(bob.address);
            expect(balance0).to.lt(balance1);
        })

        it('claimAll', async () => {
            const balance1 = await rewardToken.balanceOf(bob.address);
            await time.increase(3600 * 24 * 100);
            await bondingFarmPool.connect(bob).claimAll();
            const balance2 = await rewardToken.balanceOf(bob.address);
            expect(balance2).to.gte(balance1);
        })
    })
});
