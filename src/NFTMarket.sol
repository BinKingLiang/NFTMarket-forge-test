// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

contract NFTMarket is ERC721Holder {
    struct Listing {
        address seller;
        uint256 price;
        IERC20 paymentToken;
    }

    mapping(IERC721 => mapping(uint256 => Listing)) public listings;

    event Listed(
        IERC721 indexed nft,
        uint256 indexed tokenId,
        address seller,
        uint256 price,
        IERC20 paymentToken
    );

    event Purchased(
        IERC721 indexed nft,
        uint256 indexed tokenId,
        address buyer,
        address seller,
        uint256 price,
        IERC20 paymentToken
    );

    error NotNFTOwner();
    error AlreadyListed();
    error NotForSale();
    error InsufficientPayment();
    error InvalidPaymentToken();
    error SelfPurchase();

    function list(
        IERC721 nft,
        uint256 tokenId,
        uint256 price,
        IERC20 paymentToken
    ) external {
        if (nft.ownerOf(tokenId) != msg.sender) revert NotNFTOwner();
        if (listings[nft][tokenId].seller != address(0)) revert AlreadyListed();
        if (address(paymentToken) == address(0)) revert InvalidPaymentToken();

        nft.safeTransferFrom(msg.sender, address(this), tokenId);
        listings[nft][tokenId] = Listing(msg.sender, price, paymentToken);
        
        emit Listed(nft, tokenId, msg.sender, price, paymentToken);
    }

    function purchase(IERC721 nft, uint256 tokenId) external {
        Listing memory listing = listings[nft][tokenId];
        if (listing.seller == address(0)) revert NotForSale();
        if (listing.seller == msg.sender) revert SelfPurchase();
        
        IERC20 paymentToken = listing.paymentToken;
        uint256 price = listing.price;

        if (paymentToken.balanceOf(msg.sender) < price) 
            revert InsufficientPayment();
        
        paymentToken.transferFrom(msg.sender, listing.seller, price);
        delete listings[nft][tokenId];
        nft.safeTransferFrom(address(this), msg.sender, tokenId);
        
        emit Purchased(nft, tokenId, msg.sender, listing.seller, price, paymentToken);
    }
}
