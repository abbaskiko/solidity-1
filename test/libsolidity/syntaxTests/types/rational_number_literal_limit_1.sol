contract c {
    function bignum() public {
        uint256 a;
        a = 1e1233 / 1e1233; // 1e1233 is still fine
        a = 1e1234; // 1e1234 is too big
    }
}
// ----
<<<<<<< ours
// TypeError: (128-134): Type int_const 1000...(1227 digits omitted)...0000 is not implicitly convertible to expected type uint256.
=======
// TypeError 2826: (128-134): Invalid literal value.
>>>>>>> theirs
