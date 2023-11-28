import { ethers } from "ethers";
import { BigNumberish, BigNumber } from "@ethersproject/bignumber";

export const ether = (amount: number | string): bigint => {
    const weiString = ethers.parseEther(amount.toString());
    return weiString;
};

export const wei = (amount: number | string): bigint => {
    const weiString = ethers.parseUnits(amount.toString(), 0);
    return weiString;
};

export const gWei = (amount: number): bigint => {
    const weiString = BigNumber.from("1000000000").mul(amount);
    return weiString.toBigInt();
};

export const usdc = (amount: number): bigint => {
    const weiString = BigNumber.from("1000000").mul(amount);
    return weiString.toBigInt();
};