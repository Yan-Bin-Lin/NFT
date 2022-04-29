// Contract based on https://docs.openzeppelin.com/contracts/3.x/erc721
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title A NFT contract
/// @author Lin Yan Bin

import "./ERC721Tradable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract Creature is ERC721Tradable {
    using Strings for uint256;

    // Constants
    string public constant NFTname = "Shihuan NFT";
    string public constant shortName = "SNFT";
    string public constant version = "0.1.0";
    string public constant salt =
        "0x98ba1b54d92c3b5fbd973b4d3536f892437bc0e32736d6faf87fd1b488471308";

    uint256 public constant MAX_SUPPLY = 1024;

    // Auction data
    struct AuctionStruct {
        bool _isAuctionActive;
        uint256 tierSupply;
        uint256 maxBalance;
        uint256 maxMint;
        uint256 auctionStartTime;
        uint256 auctionTimeStep;
        uint256 auctionStartPrice;
        uint256 auctionEndPrice;
        uint256 auctionPriceStep;
    }

    AuctionStruct private AuctionState =
        AuctionStruct({
            _isAuctionActive: false,
            tierSupply: 1024,
            maxBalance: 1,
            maxMint: 1,
            auctionStartTime: 0,
            auctionTimeStep: 50000,
            auctionStartPrice: 100 ether,
            auctionEndPrice: 0 ether,
            auctionPriceStep: 5 ether
        });

    string private _baseURIExtended;
    string private _contractURI;

    mapping(string => bool) private _usedNonces;

    event TokenMinted(uint256 supply);

    // opensea rinkeby proxy address 0xf57b2c51ded3a29e6891aba85459d600256cf317
    // opensea mainet proxy address 0xa5409ec958c83c3f309868babaca7c86dcb077c1
    constructor(address _proxyRegistryAddress)
        ERC721Tradable(NFTname, shortName, _proxyRegistryAddress)
    {}

    /// @notice Allow or disallow an auction
    /// @dev Toggle _isAuctionActive
    function flipAuctionActive() public onlyOwner {
        AuctionState._isAuctionActive = !AuctionState._isAuctionActive;
    }

    /// @notice Set max total supply a time
    /// @param _tierSupply The amount to set
    function setTierSupply(uint256 _tierSupply) public onlyOwner {
        AuctionState.tierSupply = _tierSupply;
    }

    /// @notice Set max amount of nft one can mint
    /// @param _maxBalance The amount to set
    function setMaxBalance(uint256 _maxBalance) public onlyOwner {
        AuctionState.maxBalance = _maxBalance;
    }

    /// @notice Set max amount of token to mint one time
    /// @param _maxMint The amount to set
    function setMaxMint(uint256 _maxMint) public onlyOwner {
        AuctionState.maxMint = _maxMint;
    }

    /// @notice Create a new dutch auction
    /// @param _auctionStartTime The start time of auction
    /// @param _auctionTimeStep The time of discrease the price
    /// @param _auctionStartPrice The start price of a NFT
    /// @param _auctionEndPrice The final price of a NFT
    /// @param _auctionPriceStep The discrease amount of price
    function setAuction(
        uint256 _auctionStartTime,
        uint256 _auctionTimeStep,
        uint256 _auctionStartPrice,
        uint256 _auctionEndPrice,
        uint256 _auctionPriceStep
    ) public onlyOwner {
        AuctionState.auctionStartTime = _auctionStartTime;
        AuctionState.auctionTimeStep = _auctionTimeStep;
        AuctionState.auctionStartPrice = _auctionStartPrice;
        AuctionState.auctionEndPrice = _auctionEndPrice;
        AuctionState.auctionPriceStep = _auctionPriceStep;
    }

    /// @notice Get data of auction
    function getAuctionState() public view returns (AuctionStruct memory) {
        return AuctionState;
    }

    /// @notice Send out the ether of this contract
    /// @param to The address that will receive the ether
    function withdraw(address to) public onlyOwner {
        uint256 balance = address(this).balance;
        payable(to).transfer(balance);
    }

    /// @notice Direct mint by owner
    /// @param tokenQuantity mount of token to mint
    /// @param to The address to get the token
    function preserveMint(uint256 tokenQuantity, address to) public onlyOwner {
        require(
            ERC721Tradable.totalSupply() + tokenQuantity <=
                AuctionState.tierSupply,
            "Preserve mint would exceed tier supply"
        );
        require(
            ERC721Tradable.totalSupply() + tokenQuantity <= MAX_SUPPLY,
            "Preserve mint would exceed max supply"
        );
        _mintMeta(tokenQuantity, to);
        emit TokenMinted(ERC721Tradable.totalSupply());
    }

    /// @notice Get the current price of auction
    function getAuctionPrice() public view returns (uint256) {
        if (!AuctionState._isAuctionActive) {
            return 0;
        }
        if (block.timestamp < AuctionState.auctionStartTime) {
            return AuctionState.auctionStartPrice;
        }
        uint256 step = (block.timestamp - AuctionState.auctionStartTime) /
            AuctionState.auctionTimeStep;
        return
            AuctionState.auctionStartPrice >
                step * AuctionState.auctionPriceStep
                ? AuctionState.auctionStartPrice -
                    step *
                    AuctionState.auctionPriceStep
                : AuctionState.auctionEndPrice;
    }

    /// @notice Mint a new token
    /// @param nonce The nonce for hashing data
    /// @param tokenQuantity The amount to mint
    /// @param sigR Signature parameter
    /// @param sigS Signature parameter
    /// @param sigV Signature parameter
    function auctionMintMeta(
        string memory nonce,
        uint256 tokenQuantity,
        bytes32 sigR,
        bytes32 sigS,
        uint8 sigV
    ) public payable {
        require(
            ERC721Tradable.totalSupply() + tokenQuantity <=
                AuctionState.tierSupply,
            "Auction would exceed tier supply"
        );
        require(
            ERC721Tradable.totalSupply() + tokenQuantity <= MAX_SUPPLY,
            "Auction would exceed max supply"
        );
        require(
            AuctionState._isAuctionActive,
            "Auction must be active to mint OnionMetas"
        );
        require(
            block.timestamp >= AuctionState.auctionStartTime,
            "Auction not start"
        );
        require(
            balanceOf(ERC721Tradable._msgSender()) + tokenQuantity <=
                AuctionState.maxBalance,
            "Auction would exceed max balance"
        );
        require(
            tokenQuantity <= AuctionState.maxMint,
            "Auction would exceed max mint"
        );
        require(
            tokenQuantity * getAuctionPrice() <= msg.value,
            "Not enough ether sent"
        );
        require(!_usedNonces[nonce], "HASH_USED");
        require(
            verifySign(
                ERC721Tradable._msgSender(),
                tokenQuantity,
                nonce,
                sigR,
                sigS,
                sigV
            ),
            "Signature fail"
        );
        _mintMeta(tokenQuantity, ERC721Tradable._msgSender());
        emit TokenMinted(ERC721Tradable.totalSupply());
        _usedNonces[nonce] = true;
    }

    /// @notice Mint a new token
    function _mintMeta(uint256 tokenQuantity, address recipient) internal {
        //uint256 supply = totalSupply;
        for (uint256 i = 0; i < tokenQuantity; i++) {
            //_mintInternal(recipient, supply + i);
            ERC721Tradable.mintTo(recipient);
        }
    }

    /// @notice Setup base uri of this token
    /// @param baseURI_ The baseURI to set
    function setBaseURI(string memory baseURI_) external onlyOwner {
        _baseURIExtended = baseURI_;
    }

    /// @notice Get the token baseURI
    function baseTokenURI() public view override returns (string memory) {
        return _baseURIExtended;
    }

    /// @notice Get the token URI
    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );
        return string(abi.encodePacked(baseTokenURI(), tokenId.toString()));
    }

    /// @notice Setup contract uri of this smartcontract
    /// @param contractURI_ The contractURI to set
    function setContractURI(string memory contractURI_) external onlyOwner {
        _contractURI = contractURI_;
    }

    /// @notice Get the contractURI
    function contractURI() public view returns (string memory) {
        return _contractURI;
    }

    /// @notice Get hash of contract info and input data
    /// @param amount The amount to mint
    /// @param nonce The nonse for hashing data
    function _hashMsg(uint256 amount, string memory nonce)
        private
        pure
        returns (bytes32)
    {
        return
            keccak256(
                abi.encodePacked(
                    NFTname,
                    version,
                    salt,
                    Strings.toString(amount),
                    nonce
                )
            );
    }

    /// @notice Verify a signature
    /// @param signer The address of signer who sign this data
    /// @param amount The amount to mint
    /// @param nonce The nonse for hashing data
    /// @param sigR Signature parameter
    /// @param sigS Signature parameter
    /// @param sigV Signature parameter
    function verifySign(
        address signer,
        uint256 amount,
        string memory nonce,
        bytes32 sigR,
        bytes32 sigS,
        uint8 sigV
    ) public pure returns (bool) {
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes32 prefixedHashMessage = keccak256(
            abi.encodePacked(prefix, _hashMsg(amount, nonce))
        );
        return signer == ecrecover(prefixedHashMessage, sigV, sigR, sigS);
    }
}
