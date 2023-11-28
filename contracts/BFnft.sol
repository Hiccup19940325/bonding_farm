// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity =0.8.20;

import "./interface/IBFnft.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract BFnft is ERC721Enumerable, IBFnft {
    string private constant NANE = "Bonding Farm NFT";
    string private constant SYMBOL = "BFNFT";

    uint private tokenId;

    constructor() ERC721(NANE, SYMBOL) {}

    function mint(address to) external virtual returns (uint _tokenId) {
        _tokenId = tokenId;
        tokenId++;
        _mint(to, _tokenId);
    }

    function burn(uint _tokenId) external virtual {
        _burn(_tokenId);
    }
}
