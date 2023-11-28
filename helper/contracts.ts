import { ethers } from 'hardhat';
import { BaseContract } from 'ethers';

import {
    PrincipalToken,
    StakingToken,
    RewardToken,
    MockOracle,
    BondingFarmPool,
    BFnft
} from '../typechain-types'

export const deployContract = async<ContractType extends BaseContract>(
    contractName: string,
    args: any[],
    library?: {}
) => {
    const signers = await ethers.getSigners();
    const contract = await (await ethers.getContractFactory(contractName, signers[0], {
        libraries: {
            ...library
        }
    })).deploy(...args) as ContractType;
    return contract;
}

export const deployPrincipalToken = async () => {
    return await deployContract<PrincipalToken>('PrincipalToken', []);
}

export const deployStakingToken = async () => {
    return await deployContract<StakingToken>('StakingToken', []);
}

export const deployRewardToken = async () => {
    return await deployContract<RewardToken>('RewardToken', []);
}

export const deployMockOracle = async (
    _token: any,
    _price: any
) => {
    return await deployContract<MockOracle>('MockOracle', [
        _token,
        _price
    ]);
}

export const deployBFnft = async () => {
    return await deployContract<BFnft>('BFnft', []);
}

export const deployBondingFarmPool = async (
    _bfnft: any,
    _stakingToken: any,
    _rewardToken: any,
    _oracle: any
) => {
    return await deployContract<BondingFarmPool>('BondingFarmPool', [
        _bfnft,
        _stakingToken,
        _rewardToken,
        _oracle
    ]);
}