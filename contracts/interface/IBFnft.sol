// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity =0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

interface IBFnft is IERC721Enumerable {
    function mint(address to) external returns (uint tokenId);

    function burn(uint tokenId) external;
}
