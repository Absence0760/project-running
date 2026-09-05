-- The exercise grouping key stops being a function of any runtime's Unicode
-- case table (decisions § 1175).
--
-- § 790 made the WHITESPACE half provider-independent by naming code points.
-- § 830 made the CASE half collation-independent by pinning `und-x-icu`, and
-- filed what it could not afford: the ICU VERSION linked into the server, and
-- the two clients' own case tables, which are neither ICU nor each other's.
-- Measured on this stack over all 1,112,063 assignable code points, after the
-- two folds § 830 named by hand, the three rails still disagreed at
--
--   * 465 code points between web (JS full case mapping, Unicode 17.0) and
--     mobile (Dart SIMPLE case mapping from an older revision),
--   * 410 between mobile and this server,
--   *  55 between web and this server.
--
-- The key is PERSISTED -- `gym_sets.exercise_key` (server-stamped),
-- `gym_routine_exercises.exercise_key` and `exercises.name_key` (both
-- client-stamped) -- and all three columns carry a VALIDATED CHECK naming this
-- function. So each of those code points is a name one rail cannot write
-- without a 23514 from a predicate the other two agree on, and a name the
-- three would bucket as two exercises if nothing rejected it.
--
-- § 830 rejected a frozen table on cost: `translate()` over the 1,488 code
-- points carrying a non-identity lowercase mapping costs 60 us a call against
-- 0.34 us for `lower()`, re-measured here at 60.2 us against 0.35 us over
-- 200,000 calls. That was unaffordable while five RPCs re-derived the key once
-- per `gym_sets` row. § 1076 moved the fold to WRITE time, so the table's cost
-- is now bounded by how often a lifter logs a set.
--
-- -- The authority, and why SIMPLE mapping -----------------------------------
-- Unicode's SIMPLE lowercase mapping, frozen at Unicode 17.0, rendered from
-- Unicode's own data by `scripts/gen_exercise_fold_table.mjs` and committed as
-- `apps/web/src/lib/gym/exercise_fold_table.ts` +
-- `apps/mobile_android/lib/exercise_fold_table.dart`. Never hand-written: the
-- pattern §§ 852 / 855 / 856 established for the catalogue accent fold.
--
-- Simple rather than FULL mapping for one reason wearing two hats. Full
-- lowercase carries a CONTEXT (Final_Sigma) and a 1:many expansion (U+0130 to
-- `i` + U+0307, the only unconditional one in Unicode), and a per-code-point
-- table can express neither. Under the simple mapping every one of the 1,488
-- entries is 1:1, which is exactly what lets this rail be a `translate()`, and
-- U+0130 to a bare `i` is the answer § 830 already chose by hand -- so its
-- pre-fold is now a table entry and is deleted from all three rails. The
-- Final_Sigma fold stays, because it is a context and not a case: the table
-- always answers U+03C3, and folding a typed U+03C2 onto it is what makes an
-- all-caps Greek spelling meet its lower-case one.
--
-- -- Measured before shipping -------------------------------------------------
--   * The three rails agree EXACTLY. Every assignable code point through each
--     rail's whole `normaliseExerciseName` pipeline, chunk-hashed: SQL, JS and
--     Dart all answer md5 76a152d0e2a86b0b39a311597b42633b. Residual
--     disagreement 465 / 410 / 55 becomes 0 / 0 / 0.
--   * WEB DOES NOT MOVE. The frozen table is web's own answer: over 8,896,512
--     strings (every code point in eight contexts -- alone, ASCII-flanked,
--     doubled, before a combining acute, after a Greek all-caps word, before a
--     capital sigma) the old and new web pipelines differ on ZERO.
--   * THIS RAIL moves at exactly 55 code points, and only ever by folding one
--     it used to leave alone: measured against the frozen table, ICU root
--     folds NOTHING the table does not, and the single differing VALUE is
--     U+0130, whose old `i` + U+0307 the hand-written pre-fold already
--     replaced with the bare `i` the table carries. So no stored key changes
--     value; 55 gain a fold. U+1C89, U+A7CB/CC/CE/D2/D4/DA/DC, the Garay block
--     U+10D50-65 and the Sidetic block from U+16EA0 are the population.
--   * Blast radius on real rows, measured on the local stack: 0 of 23
--     `gym_sets`, 0 of 4 `gym_routine_exercises` and 0 of 43 `exercises` rows
--     re-key, and no `exercises` unique-key collision arises. The backfills
--     and the collision merge run anyway, for the reason § 790 gave -- "every
--     client build that ever wrote a row conformed" is a claim about history a
--     migration cannot verify.
--   * Cost. `translate()` over the full table is 60.2 us a call. The ASCII
--     fast path below takes an all-ASCII name -- every exercise name the seed
--     and the shipped catalogue carry -- to 2.5 us, against 4.5 us for the
--     whole of the old `normalise_exercise_name`. A name with any non-ASCII
--     character pays the full 60 us, which is now a per-WRITE cost: a logged
--     session of 40 sets spends 2.4 ms of folding, and the same figure is what
--     the backfill and the three VALIDATE scans below pay per row.
--
-- -- Why the fast path is answer-identical, not an approximation --------------
-- `octet_length(p) = length(p)` is true exactly when every character is one
-- UTF-8 byte, which is exactly ASCII; it names no collation and no locale. The
-- table's ASCII half is exactly A-Z to a-z and it folds no other ASCII code
-- point, so for an all-ASCII input the 26-pair `translate` and the 1,488-pair
-- one visit the same characters and answer the same. Both clients' suites and
-- `scripts/check_shared_constants.mjs` pin that ASCII half, so the branch
-- cannot drift away from the table underneath it.
--
-- -- Lock impact (migration_locks.md) ----------------------------------------
-- CREATE OR REPLACE FUNCTION locks the pg_proc entry only. `gym_sets`'
-- backfill is keyset-paginated in 5,000-row chunks, the shape 20270706000002
-- measured at 6.94 s against 129.5 s for the offset form; the two bounded
-- tables keep the batched-predicate form. The three CHECKs are DROPPED and
-- re-added NOT VALID (metadata-only, ACCESS EXCLUSIVE for the catalogue update
-- alone) and then VALIDATEd under SHARE UPDATE EXCLUSIVE, which lets reads and
-- writes through. Re-adding is what re-proves them: the constraint EXPRESSION
-- is unchanged, so Postgres leaves `convalidated` true when the function
-- underneath it moves, and every stored row would otherwise carry an
-- unverified claim (§ 830 established this two-step; there are three
-- constraints now because § 1076 added `gym_sets`').

create or replace function public.exercise_fold_case(p_name text)
returns text
language sql
immutable
parallel safe
returns null on null input
set search_path = ''
as $$
  select case
    when octet_length(p_name) = length(p_name)
      then translate(p_name, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz')
      else translate(
        p_name,
          U&'\0041\0042\0043\0044\0045\0046\0047\0048\0049\004A\004B\004C\004D\004E\004F\0050'
          '\0051\0052\0053\0054\0055\0056\0057\0058\0059\005A\00C0\00C1\00C2\00C3\00C4\00C5'
          '\00C6\00C7\00C8\00C9\00CA\00CB\00CC\00CD\00CE\00CF\00D0\00D1\00D2\00D3\00D4\00D5'
          '\00D6\00D8\00D9\00DA\00DB\00DC\00DD\00DE\0100\0102\0104\0106\0108\010A\010C\010E'
          '\0110\0112\0114\0116\0118\011A\011C\011E\0120\0122\0124\0126\0128\012A\012C\012E'
          '\0130\0132\0134\0136\0139\013B\013D\013F\0141\0143\0145\0147\014A\014C\014E\0150'
          '\0152\0154\0156\0158\015A\015C\015E\0160\0162\0164\0166\0168\016A\016C\016E\0170'
          '\0172\0174\0176\0178\0179\017B\017D\0181\0182\0184\0186\0187\0189\018A\018B\018E'
          '\018F\0190\0191\0193\0194\0196\0197\0198\019C\019D\019F\01A0\01A2\01A4\01A6\01A7'
          '\01A9\01AC\01AE\01AF\01B1\01B2\01B3\01B5\01B7\01B8\01BC\01C4\01C5\01C7\01C8\01CA'
          '\01CB\01CD\01CF\01D1\01D3\01D5\01D7\01D9\01DB\01DE\01E0\01E2\01E4\01E6\01E8\01EA'
          '\01EC\01EE\01F1\01F2\01F4\01F6\01F7\01F8\01FA\01FC\01FE\0200\0202\0204\0206\0208'
          '\020A\020C\020E\0210\0212\0214\0216\0218\021A\021C\021E\0220\0222\0224\0226\0228'
          '\022A\022C\022E\0230\0232\023A\023B\023D\023E\0241\0243\0244\0245\0246\0248\024A'
          '\024C\024E\0370\0372\0376\037F\0386\0388\0389\038A\038C\038E\038F\0391\0392\0393'
          '\0394\0395\0396\0397\0398\0399\039A\039B\039C\039D\039E\039F\03A0\03A1\03A3\03A4'
          '\03A5\03A6\03A7\03A8\03A9\03AA\03AB\03CF\03D8\03DA\03DC\03DE\03E0\03E2\03E4\03E6'
          '\03E8\03EA\03EC\03EE\03F4\03F7\03F9\03FA\03FD\03FE\03FF\0400\0401\0402\0403\0404'
          '\0405\0406\0407\0408\0409\040A\040B\040C\040D\040E\040F\0410\0411\0412\0413\0414'
          '\0415\0416\0417\0418\0419\041A\041B\041C\041D\041E\041F\0420\0421\0422\0423\0424'
          '\0425\0426\0427\0428\0429\042A\042B\042C\042D\042E\042F\0460\0462\0464\0466\0468'
          '\046A\046C\046E\0470\0472\0474\0476\0478\047A\047C\047E\0480\048A\048C\048E\0490'
          '\0492\0494\0496\0498\049A\049C\049E\04A0\04A2\04A4\04A6\04A8\04AA\04AC\04AE\04B0'
          '\04B2\04B4\04B6\04B8\04BA\04BC\04BE\04C0\04C1\04C3\04C5\04C7\04C9\04CB\04CD\04D0'
          '\04D2\04D4\04D6\04D8\04DA\04DC\04DE\04E0\04E2\04E4\04E6\04E8\04EA\04EC\04EE\04F0'
          '\04F2\04F4\04F6\04F8\04FA\04FC\04FE\0500\0502\0504\0506\0508\050A\050C\050E\0510'
          '\0512\0514\0516\0518\051A\051C\051E\0520\0522\0524\0526\0528\052A\052C\052E\0531'
          '\0532\0533\0534\0535\0536\0537\0538\0539\053A\053B\053C\053D\053E\053F\0540\0541'
          '\0542\0543\0544\0545\0546\0547\0548\0549\054A\054B\054C\054D\054E\054F\0550\0551'
          '\0552\0553\0554\0555\0556\10A0\10A1\10A2\10A3\10A4\10A5\10A6\10A7\10A8\10A9\10AA'
          '\10AB\10AC\10AD\10AE\10AF\10B0\10B1\10B2\10B3\10B4\10B5\10B6\10B7\10B8\10B9\10BA'
          '\10BB\10BC\10BD\10BE\10BF\10C0\10C1\10C2\10C3\10C4\10C5\10C7\10CD\13A0\13A1\13A2'
          '\13A3\13A4\13A5\13A6\13A7\13A8\13A9\13AA\13AB\13AC\13AD\13AE\13AF\13B0\13B1\13B2'
          '\13B3\13B4\13B5\13B6\13B7\13B8\13B9\13BA\13BB\13BC\13BD\13BE\13BF\13C0\13C1\13C2'
          '\13C3\13C4\13C5\13C6\13C7\13C8\13C9\13CA\13CB\13CC\13CD\13CE\13CF\13D0\13D1\13D2'
          '\13D3\13D4\13D5\13D6\13D7\13D8\13D9\13DA\13DB\13DC\13DD\13DE\13DF\13E0\13E1\13E2'
          '\13E3\13E4\13E5\13E6\13E7\13E8\13E9\13EA\13EB\13EC\13ED\13EE\13EF\13F0\13F1\13F2'
          '\13F3\13F4\13F5\1C89\1C90\1C91\1C92\1C93\1C94\1C95\1C96\1C97\1C98\1C99\1C9A\1C9B'
          '\1C9C\1C9D\1C9E\1C9F\1CA0\1CA1\1CA2\1CA3\1CA4\1CA5\1CA6\1CA7\1CA8\1CA9\1CAA\1CAB'
          '\1CAC\1CAD\1CAE\1CAF\1CB0\1CB1\1CB2\1CB3\1CB4\1CB5\1CB6\1CB7\1CB8\1CB9\1CBA\1CBD'
          '\1CBE\1CBF\1E00\1E02\1E04\1E06\1E08\1E0A\1E0C\1E0E\1E10\1E12\1E14\1E16\1E18\1E1A'
          '\1E1C\1E1E\1E20\1E22\1E24\1E26\1E28\1E2A\1E2C\1E2E\1E30\1E32\1E34\1E36\1E38\1E3A'
          '\1E3C\1E3E\1E40\1E42\1E44\1E46\1E48\1E4A\1E4C\1E4E\1E50\1E52\1E54\1E56\1E58\1E5A'
          '\1E5C\1E5E\1E60\1E62\1E64\1E66\1E68\1E6A\1E6C\1E6E\1E70\1E72\1E74\1E76\1E78\1E7A'
          '\1E7C\1E7E\1E80\1E82\1E84\1E86\1E88\1E8A\1E8C\1E8E\1E90\1E92\1E94\1E9E\1EA0\1EA2'
          '\1EA4\1EA6\1EA8\1EAA\1EAC\1EAE\1EB0\1EB2\1EB4\1EB6\1EB8\1EBA\1EBC\1EBE\1EC0\1EC2'
          '\1EC4\1EC6\1EC8\1ECA\1ECC\1ECE\1ED0\1ED2\1ED4\1ED6\1ED8\1EDA\1EDC\1EDE\1EE0\1EE2'
          '\1EE4\1EE6\1EE8\1EEA\1EEC\1EEE\1EF0\1EF2\1EF4\1EF6\1EF8\1EFA\1EFC\1EFE\1F08\1F09'
          '\1F0A\1F0B\1F0C\1F0D\1F0E\1F0F\1F18\1F19\1F1A\1F1B\1F1C\1F1D\1F28\1F29\1F2A\1F2B'
          '\1F2C\1F2D\1F2E\1F2F\1F38\1F39\1F3A\1F3B\1F3C\1F3D\1F3E\1F3F\1F48\1F49\1F4A\1F4B'
          '\1F4C\1F4D\1F59\1F5B\1F5D\1F5F\1F68\1F69\1F6A\1F6B\1F6C\1F6D\1F6E\1F6F\1F88\1F89'
          '\1F8A\1F8B\1F8C\1F8D\1F8E\1F8F\1F98\1F99\1F9A\1F9B\1F9C\1F9D\1F9E\1F9F\1FA8\1FA9'
          '\1FAA\1FAB\1FAC\1FAD\1FAE\1FAF\1FB8\1FB9\1FBA\1FBB\1FBC\1FC8\1FC9\1FCA\1FCB\1FCC'
          '\1FD8\1FD9\1FDA\1FDB\1FE8\1FE9\1FEA\1FEB\1FEC\1FF8\1FF9\1FFA\1FFB\1FFC\2126\212A'
          '\212B\2132\2160\2161\2162\2163\2164\2165\2166\2167\2168\2169\216A\216B\216C\216D'
          '\216E\216F\2183\24B6\24B7\24B8\24B9\24BA\24BB\24BC\24BD\24BE\24BF\24C0\24C1\24C2'
          '\24C3\24C4\24C5\24C6\24C7\24C8\24C9\24CA\24CB\24CC\24CD\24CE\24CF\2C00\2C01\2C02'
          '\2C03\2C04\2C05\2C06\2C07\2C08\2C09\2C0A\2C0B\2C0C\2C0D\2C0E\2C0F\2C10\2C11\2C12'
          '\2C13\2C14\2C15\2C16\2C17\2C18\2C19\2C1A\2C1B\2C1C\2C1D\2C1E\2C1F\2C20\2C21\2C22'
          '\2C23\2C24\2C25\2C26\2C27\2C28\2C29\2C2A\2C2B\2C2C\2C2D\2C2E\2C2F\2C60\2C62\2C63'
          '\2C64\2C67\2C69\2C6B\2C6D\2C6E\2C6F\2C70\2C72\2C75\2C7E\2C7F\2C80\2C82\2C84\2C86'
          '\2C88\2C8A\2C8C\2C8E\2C90\2C92\2C94\2C96\2C98\2C9A\2C9C\2C9E\2CA0\2CA2\2CA4\2CA6'
          '\2CA8\2CAA\2CAC\2CAE\2CB0\2CB2\2CB4\2CB6\2CB8\2CBA\2CBC\2CBE\2CC0\2CC2\2CC4\2CC6'
          '\2CC8\2CCA\2CCC\2CCE\2CD0\2CD2\2CD4\2CD6\2CD8\2CDA\2CDC\2CDE\2CE0\2CE2\2CEB\2CED'
          '\2CF2\A640\A642\A644\A646\A648\A64A\A64C\A64E\A650\A652\A654\A656\A658\A65A\A65C'
          '\A65E\A660\A662\A664\A666\A668\A66A\A66C\A680\A682\A684\A686\A688\A68A\A68C\A68E'
          '\A690\A692\A694\A696\A698\A69A\A722\A724\A726\A728\A72A\A72C\A72E\A732\A734\A736'
          '\A738\A73A\A73C\A73E\A740\A742\A744\A746\A748\A74A\A74C\A74E\A750\A752\A754\A756'
          '\A758\A75A\A75C\A75E\A760\A762\A764\A766\A768\A76A\A76C\A76E\A779\A77B\A77D\A77E'
          '\A780\A782\A784\A786\A78B\A78D\A790\A792\A796\A798\A79A\A79C\A79E\A7A0\A7A2\A7A4'
          '\A7A6\A7A8\A7AA\A7AB\A7AC\A7AD\A7AE\A7B0\A7B1\A7B2\A7B3\A7B4\A7B6\A7B8\A7BA\A7BC'
          '\A7BE\A7C0\A7C2\A7C4\A7C5\A7C6\A7C7\A7C9\A7CB\A7CC\A7CE\A7D0\A7D2\A7D4\A7D6\A7D8'
          '\A7DA\A7DC\A7F5\FF21\FF22\FF23\FF24\FF25\FF26\FF27\FF28\FF29\FF2A\FF2B\FF2C\FF2D'
          '\FF2E\FF2F\FF30\FF31\FF32\FF33\FF34\FF35\FF36\FF37\FF38\FF39\FF3A\+010400\+010401\+010402'
          '\+010403\+010404\+010405\+010406\+010407\+010408\+010409\+01040A\+01040B\+01040C\+01040D\+01040E\+01040F\+010410\+010411\+010412'
          '\+010413\+010414\+010415\+010416\+010417\+010418\+010419\+01041A\+01041B\+01041C\+01041D\+01041E\+01041F\+010420\+010421\+010422'
          '\+010423\+010424\+010425\+010426\+010427\+0104B0\+0104B1\+0104B2\+0104B3\+0104B4\+0104B5\+0104B6\+0104B7\+0104B8\+0104B9\+0104BA'
          '\+0104BB\+0104BC\+0104BD\+0104BE\+0104BF\+0104C0\+0104C1\+0104C2\+0104C3\+0104C4\+0104C5\+0104C6\+0104C7\+0104C8\+0104C9\+0104CA'
          '\+0104CB\+0104CC\+0104CD\+0104CE\+0104CF\+0104D0\+0104D1\+0104D2\+0104D3\+010570\+010571\+010572\+010573\+010574\+010575\+010576'
          '\+010577\+010578\+010579\+01057A\+01057C\+01057D\+01057E\+01057F\+010580\+010581\+010582\+010583\+010584\+010585\+010586\+010587'
          '\+010588\+010589\+01058A\+01058C\+01058D\+01058E\+01058F\+010590\+010591\+010592\+010594\+010595\+010C80\+010C81\+010C82\+010C83'
          '\+010C84\+010C85\+010C86\+010C87\+010C88\+010C89\+010C8A\+010C8B\+010C8C\+010C8D\+010C8E\+010C8F\+010C90\+010C91\+010C92\+010C93'
          '\+010C94\+010C95\+010C96\+010C97\+010C98\+010C99\+010C9A\+010C9B\+010C9C\+010C9D\+010C9E\+010C9F\+010CA0\+010CA1\+010CA2\+010CA3'
          '\+010CA4\+010CA5\+010CA6\+010CA7\+010CA8\+010CA9\+010CAA\+010CAB\+010CAC\+010CAD\+010CAE\+010CAF\+010CB0\+010CB1\+010CB2\+010D50'
          '\+010D51\+010D52\+010D53\+010D54\+010D55\+010D56\+010D57\+010D58\+010D59\+010D5A\+010D5B\+010D5C\+010D5D\+010D5E\+010D5F\+010D60'
          '\+010D61\+010D62\+010D63\+010D64\+010D65\+0118A0\+0118A1\+0118A2\+0118A3\+0118A4\+0118A5\+0118A6\+0118A7\+0118A8\+0118A9\+0118AA'
          '\+0118AB\+0118AC\+0118AD\+0118AE\+0118AF\+0118B0\+0118B1\+0118B2\+0118B3\+0118B4\+0118B5\+0118B6\+0118B7\+0118B8\+0118B9\+0118BA'
          '\+0118BB\+0118BC\+0118BD\+0118BE\+0118BF\+016E40\+016E41\+016E42\+016E43\+016E44\+016E45\+016E46\+016E47\+016E48\+016E49\+016E4A'
          '\+016E4B\+016E4C\+016E4D\+016E4E\+016E4F\+016E50\+016E51\+016E52\+016E53\+016E54\+016E55\+016E56\+016E57\+016E58\+016E59\+016E5A'
          '\+016E5B\+016E5C\+016E5D\+016E5E\+016E5F\+016EA0\+016EA1\+016EA2\+016EA3\+016EA4\+016EA5\+016EA6\+016EA7\+016EA8\+016EA9\+016EAA'
          '\+016EAB\+016EAC\+016EAD\+016EAE\+016EAF\+016EB0\+016EB1\+016EB2\+016EB3\+016EB4\+016EB5\+016EB6\+016EB7\+016EB8\+01E900\+01E901'
          '\+01E902\+01E903\+01E904\+01E905\+01E906\+01E907\+01E908\+01E909\+01E90A\+01E90B\+01E90C\+01E90D\+01E90E\+01E90F\+01E910\+01E911'
          '\+01E912\+01E913\+01E914\+01E915\+01E916\+01E917\+01E918\+01E919\+01E91A\+01E91B\+01E91C\+01E91D\+01E91E\+01E91F\+01E920\+01E921',
          U&'\0061\0062\0063\0064\0065\0066\0067\0068\0069\006A\006B\006C\006D\006E\006F\0070'
          '\0071\0072\0073\0074\0075\0076\0077\0078\0079\007A\00E0\00E1\00E2\00E3\00E4\00E5'
          '\00E6\00E7\00E8\00E9\00EA\00EB\00EC\00ED\00EE\00EF\00F0\00F1\00F2\00F3\00F4\00F5'
          '\00F6\00F8\00F9\00FA\00FB\00FC\00FD\00FE\0101\0103\0105\0107\0109\010B\010D\010F'
          '\0111\0113\0115\0117\0119\011B\011D\011F\0121\0123\0125\0127\0129\012B\012D\012F'
          '\0069\0133\0135\0137\013A\013C\013E\0140\0142\0144\0146\0148\014B\014D\014F\0151'
          '\0153\0155\0157\0159\015B\015D\015F\0161\0163\0165\0167\0169\016B\016D\016F\0171'
          '\0173\0175\0177\00FF\017A\017C\017E\0253\0183\0185\0254\0188\0256\0257\018C\01DD'
          '\0259\025B\0192\0260\0263\0269\0268\0199\026F\0272\0275\01A1\01A3\01A5\0280\01A8'
          '\0283\01AD\0288\01B0\028A\028B\01B4\01B6\0292\01B9\01BD\01C6\01C6\01C9\01C9\01CC'
          '\01CC\01CE\01D0\01D2\01D4\01D6\01D8\01DA\01DC\01DF\01E1\01E3\01E5\01E7\01E9\01EB'
          '\01ED\01EF\01F3\01F3\01F5\0195\01BF\01F9\01FB\01FD\01FF\0201\0203\0205\0207\0209'
          '\020B\020D\020F\0211\0213\0215\0217\0219\021B\021D\021F\019E\0223\0225\0227\0229'
          '\022B\022D\022F\0231\0233\2C65\023C\019A\2C66\0242\0180\0289\028C\0247\0249\024B'
          '\024D\024F\0371\0373\0377\03F3\03AC\03AD\03AE\03AF\03CC\03CD\03CE\03B1\03B2\03B3'
          '\03B4\03B5\03B6\03B7\03B8\03B9\03BA\03BB\03BC\03BD\03BE\03BF\03C0\03C1\03C3\03C4'
          '\03C5\03C6\03C7\03C8\03C9\03CA\03CB\03D7\03D9\03DB\03DD\03DF\03E1\03E3\03E5\03E7'
          '\03E9\03EB\03ED\03EF\03B8\03F8\03F2\03FB\037B\037C\037D\0450\0451\0452\0453\0454'
          '\0455\0456\0457\0458\0459\045A\045B\045C\045D\045E\045F\0430\0431\0432\0433\0434'
          '\0435\0436\0437\0438\0439\043A\043B\043C\043D\043E\043F\0440\0441\0442\0443\0444'
          '\0445\0446\0447\0448\0449\044A\044B\044C\044D\044E\044F\0461\0463\0465\0467\0469'
          '\046B\046D\046F\0471\0473\0475\0477\0479\047B\047D\047F\0481\048B\048D\048F\0491'
          '\0493\0495\0497\0499\049B\049D\049F\04A1\04A3\04A5\04A7\04A9\04AB\04AD\04AF\04B1'
          '\04B3\04B5\04B7\04B9\04BB\04BD\04BF\04CF\04C2\04C4\04C6\04C8\04CA\04CC\04CE\04D1'
          '\04D3\04D5\04D7\04D9\04DB\04DD\04DF\04E1\04E3\04E5\04E7\04E9\04EB\04ED\04EF\04F1'
          '\04F3\04F5\04F7\04F9\04FB\04FD\04FF\0501\0503\0505\0507\0509\050B\050D\050F\0511'
          '\0513\0515\0517\0519\051B\051D\051F\0521\0523\0525\0527\0529\052B\052D\052F\0561'
          '\0562\0563\0564\0565\0566\0567\0568\0569\056A\056B\056C\056D\056E\056F\0570\0571'
          '\0572\0573\0574\0575\0576\0577\0578\0579\057A\057B\057C\057D\057E\057F\0580\0581'
          '\0582\0583\0584\0585\0586\2D00\2D01\2D02\2D03\2D04\2D05\2D06\2D07\2D08\2D09\2D0A'
          '\2D0B\2D0C\2D0D\2D0E\2D0F\2D10\2D11\2D12\2D13\2D14\2D15\2D16\2D17\2D18\2D19\2D1A'
          '\2D1B\2D1C\2D1D\2D1E\2D1F\2D20\2D21\2D22\2D23\2D24\2D25\2D27\2D2D\AB70\AB71\AB72'
          '\AB73\AB74\AB75\AB76\AB77\AB78\AB79\AB7A\AB7B\AB7C\AB7D\AB7E\AB7F\AB80\AB81\AB82'
          '\AB83\AB84\AB85\AB86\AB87\AB88\AB89\AB8A\AB8B\AB8C\AB8D\AB8E\AB8F\AB90\AB91\AB92'
          '\AB93\AB94\AB95\AB96\AB97\AB98\AB99\AB9A\AB9B\AB9C\AB9D\AB9E\AB9F\ABA0\ABA1\ABA2'
          '\ABA3\ABA4\ABA5\ABA6\ABA7\ABA8\ABA9\ABAA\ABAB\ABAC\ABAD\ABAE\ABAF\ABB0\ABB1\ABB2'
          '\ABB3\ABB4\ABB5\ABB6\ABB7\ABB8\ABB9\ABBA\ABBB\ABBC\ABBD\ABBE\ABBF\13F8\13F9\13FA'
          '\13FB\13FC\13FD\1C8A\10D0\10D1\10D2\10D3\10D4\10D5\10D6\10D7\10D8\10D9\10DA\10DB'
          '\10DC\10DD\10DE\10DF\10E0\10E1\10E2\10E3\10E4\10E5\10E6\10E7\10E8\10E9\10EA\10EB'
          '\10EC\10ED\10EE\10EF\10F0\10F1\10F2\10F3\10F4\10F5\10F6\10F7\10F8\10F9\10FA\10FD'
          '\10FE\10FF\1E01\1E03\1E05\1E07\1E09\1E0B\1E0D\1E0F\1E11\1E13\1E15\1E17\1E19\1E1B'
          '\1E1D\1E1F\1E21\1E23\1E25\1E27\1E29\1E2B\1E2D\1E2F\1E31\1E33\1E35\1E37\1E39\1E3B'
          '\1E3D\1E3F\1E41\1E43\1E45\1E47\1E49\1E4B\1E4D\1E4F\1E51\1E53\1E55\1E57\1E59\1E5B'
          '\1E5D\1E5F\1E61\1E63\1E65\1E67\1E69\1E6B\1E6D\1E6F\1E71\1E73\1E75\1E77\1E79\1E7B'
          '\1E7D\1E7F\1E81\1E83\1E85\1E87\1E89\1E8B\1E8D\1E8F\1E91\1E93\1E95\00DF\1EA1\1EA3'
          '\1EA5\1EA7\1EA9\1EAB\1EAD\1EAF\1EB1\1EB3\1EB5\1EB7\1EB9\1EBB\1EBD\1EBF\1EC1\1EC3'
          '\1EC5\1EC7\1EC9\1ECB\1ECD\1ECF\1ED1\1ED3\1ED5\1ED7\1ED9\1EDB\1EDD\1EDF\1EE1\1EE3'
          '\1EE5\1EE7\1EE9\1EEB\1EED\1EEF\1EF1\1EF3\1EF5\1EF7\1EF9\1EFB\1EFD\1EFF\1F00\1F01'
          '\1F02\1F03\1F04\1F05\1F06\1F07\1F10\1F11\1F12\1F13\1F14\1F15\1F20\1F21\1F22\1F23'
          '\1F24\1F25\1F26\1F27\1F30\1F31\1F32\1F33\1F34\1F35\1F36\1F37\1F40\1F41\1F42\1F43'
          '\1F44\1F45\1F51\1F53\1F55\1F57\1F60\1F61\1F62\1F63\1F64\1F65\1F66\1F67\1F80\1F81'
          '\1F82\1F83\1F84\1F85\1F86\1F87\1F90\1F91\1F92\1F93\1F94\1F95\1F96\1F97\1FA0\1FA1'
          '\1FA2\1FA3\1FA4\1FA5\1FA6\1FA7\1FB0\1FB1\1F70\1F71\1FB3\1F72\1F73\1F74\1F75\1FC3'
          '\1FD0\1FD1\1F76\1F77\1FE0\1FE1\1F7A\1F7B\1FE5\1F78\1F79\1F7C\1F7D\1FF3\03C9\006B'
          '\00E5\214E\2170\2171\2172\2173\2174\2175\2176\2177\2178\2179\217A\217B\217C\217D'
          '\217E\217F\2184\24D0\24D1\24D2\24D3\24D4\24D5\24D6\24D7\24D8\24D9\24DA\24DB\24DC'
          '\24DD\24DE\24DF\24E0\24E1\24E2\24E3\24E4\24E5\24E6\24E7\24E8\24E9\2C30\2C31\2C32'
          '\2C33\2C34\2C35\2C36\2C37\2C38\2C39\2C3A\2C3B\2C3C\2C3D\2C3E\2C3F\2C40\2C41\2C42'
          '\2C43\2C44\2C45\2C46\2C47\2C48\2C49\2C4A\2C4B\2C4C\2C4D\2C4E\2C4F\2C50\2C51\2C52'
          '\2C53\2C54\2C55\2C56\2C57\2C58\2C59\2C5A\2C5B\2C5C\2C5D\2C5E\2C5F\2C61\026B\1D7D'
          '\027D\2C68\2C6A\2C6C\0251\0271\0250\0252\2C73\2C76\023F\0240\2C81\2C83\2C85\2C87'
          '\2C89\2C8B\2C8D\2C8F\2C91\2C93\2C95\2C97\2C99\2C9B\2C9D\2C9F\2CA1\2CA3\2CA5\2CA7'
          '\2CA9\2CAB\2CAD\2CAF\2CB1\2CB3\2CB5\2CB7\2CB9\2CBB\2CBD\2CBF\2CC1\2CC3\2CC5\2CC7'
          '\2CC9\2CCB\2CCD\2CCF\2CD1\2CD3\2CD5\2CD7\2CD9\2CDB\2CDD\2CDF\2CE1\2CE3\2CEC\2CEE'
          '\2CF3\A641\A643\A645\A647\A649\A64B\A64D\A64F\A651\A653\A655\A657\A659\A65B\A65D'
          '\A65F\A661\A663\A665\A667\A669\A66B\A66D\A681\A683\A685\A687\A689\A68B\A68D\A68F'
          '\A691\A693\A695\A697\A699\A69B\A723\A725\A727\A729\A72B\A72D\A72F\A733\A735\A737'
          '\A739\A73B\A73D\A73F\A741\A743\A745\A747\A749\A74B\A74D\A74F\A751\A753\A755\A757'
          '\A759\A75B\A75D\A75F\A761\A763\A765\A767\A769\A76B\A76D\A76F\A77A\A77C\1D79\A77F'
          '\A781\A783\A785\A787\A78C\0265\A791\A793\A797\A799\A79B\A79D\A79F\A7A1\A7A3\A7A5'
          '\A7A7\A7A9\0266\025C\0261\026C\026A\029E\0287\029D\AB53\A7B5\A7B7\A7B9\A7BB\A7BD'
          '\A7BF\A7C1\A7C3\A794\0282\1D8E\A7C8\A7CA\0264\A7CD\A7CF\A7D1\A7D3\A7D5\A7D7\A7D9'
          '\A7DB\019B\A7F6\FF41\FF42\FF43\FF44\FF45\FF46\FF47\FF48\FF49\FF4A\FF4B\FF4C\FF4D'
          '\FF4E\FF4F\FF50\FF51\FF52\FF53\FF54\FF55\FF56\FF57\FF58\FF59\FF5A\+010428\+010429\+01042A'
          '\+01042B\+01042C\+01042D\+01042E\+01042F\+010430\+010431\+010432\+010433\+010434\+010435\+010436\+010437\+010438\+010439\+01043A'
          '\+01043B\+01043C\+01043D\+01043E\+01043F\+010440\+010441\+010442\+010443\+010444\+010445\+010446\+010447\+010448\+010449\+01044A'
          '\+01044B\+01044C\+01044D\+01044E\+01044F\+0104D8\+0104D9\+0104DA\+0104DB\+0104DC\+0104DD\+0104DE\+0104DF\+0104E0\+0104E1\+0104E2'
          '\+0104E3\+0104E4\+0104E5\+0104E6\+0104E7\+0104E8\+0104E9\+0104EA\+0104EB\+0104EC\+0104ED\+0104EE\+0104EF\+0104F0\+0104F1\+0104F2'
          '\+0104F3\+0104F4\+0104F5\+0104F6\+0104F7\+0104F8\+0104F9\+0104FA\+0104FB\+010597\+010598\+010599\+01059A\+01059B\+01059C\+01059D'
          '\+01059E\+01059F\+0105A0\+0105A1\+0105A3\+0105A4\+0105A5\+0105A6\+0105A7\+0105A8\+0105A9\+0105AA\+0105AB\+0105AC\+0105AD\+0105AE'
          '\+0105AF\+0105B0\+0105B1\+0105B3\+0105B4\+0105B5\+0105B6\+0105B7\+0105B8\+0105B9\+0105BB\+0105BC\+010CC0\+010CC1\+010CC2\+010CC3'
          '\+010CC4\+010CC5\+010CC6\+010CC7\+010CC8\+010CC9\+010CCA\+010CCB\+010CCC\+010CCD\+010CCE\+010CCF\+010CD0\+010CD1\+010CD2\+010CD3'
          '\+010CD4\+010CD5\+010CD6\+010CD7\+010CD8\+010CD9\+010CDA\+010CDB\+010CDC\+010CDD\+010CDE\+010CDF\+010CE0\+010CE1\+010CE2\+010CE3'
          '\+010CE4\+010CE5\+010CE6\+010CE7\+010CE8\+010CE9\+010CEA\+010CEB\+010CEC\+010CED\+010CEE\+010CEF\+010CF0\+010CF1\+010CF2\+010D70'
          '\+010D71\+010D72\+010D73\+010D74\+010D75\+010D76\+010D77\+010D78\+010D79\+010D7A\+010D7B\+010D7C\+010D7D\+010D7E\+010D7F\+010D80'
          '\+010D81\+010D82\+010D83\+010D84\+010D85\+0118C0\+0118C1\+0118C2\+0118C3\+0118C4\+0118C5\+0118C6\+0118C7\+0118C8\+0118C9\+0118CA'
          '\+0118CB\+0118CC\+0118CD\+0118CE\+0118CF\+0118D0\+0118D1\+0118D2\+0118D3\+0118D4\+0118D5\+0118D6\+0118D7\+0118D8\+0118D9\+0118DA'
          '\+0118DB\+0118DC\+0118DD\+0118DE\+0118DF\+016E60\+016E61\+016E62\+016E63\+016E64\+016E65\+016E66\+016E67\+016E68\+016E69\+016E6A'
          '\+016E6B\+016E6C\+016E6D\+016E6E\+016E6F\+016E70\+016E71\+016E72\+016E73\+016E74\+016E75\+016E76\+016E77\+016E78\+016E79\+016E7A'
          '\+016E7B\+016E7C\+016E7D\+016E7E\+016E7F\+016EBB\+016EBC\+016EBD\+016EBE\+016EBF\+016EC0\+016EC1\+016EC2\+016EC3\+016EC4\+016EC5'
          '\+016EC6\+016EC7\+016EC8\+016EC9\+016ECA\+016ECB\+016ECC\+016ECD\+016ECE\+016ECF\+016ED0\+016ED1\+016ED2\+016ED3\+01E922\+01E923'
          '\+01E924\+01E925\+01E926\+01E927\+01E928\+01E929\+01E92A\+01E92B\+01E92C\+01E92D\+01E92E\+01E92F\+01E930\+01E931\+01E932\+01E933'
          '\+01E934\+01E935\+01E936\+01E937\+01E938\+01E939\+01E93A\+01E93B\+01E93C\+01E93D\+01E93E\+01E93F\+01E940\+01E941\+01E942\+01E943'
      )
  end;
$$;

comment on function public.exercise_fold_case(text) is
  'Unicode SIMPLE lowercase mapping frozen at Unicode 17.0: 1,488 1:1 code-point folds, with an answer-identical 26-pair fast path for an all-ASCII name. Depends on neither the database collation nor the linked ICU version. Must stay identical to EXERCISE_FOLD_KEYS/VALUES in apps/web/src/lib/gym/exercise_fold_table.ts and kExerciseFoldKeys/Values in apps/mobile_android/lib/exercise_fold_table.dart, which scripts/gen_exercise_fold_table.mjs renders and scripts/check_shared_constants.mjs compares.';

-- The grant list is decided by who WRITES the three keyed tables, because a
-- CHECK naming a function ACL-checks it against the INSERTING role -- and this
-- one is reached THROUGH `normalise_exercise_name`, which is SECURITY INVOKER,
-- so the inserting role needs EXECUTE on both. `anon` has to be revoked BY
-- NAME: Supabase's default privileges hand every new function an EXPLICIT anon
-- grant that `from public` does not reach (§ 790).
revoke execute on function public.exercise_fold_case(text) from public, anon;
grant  execute on function public.exercise_fold_case(text) to authenticated;
grant  execute on function public.exercise_fold_case(text) to service_role;

-- The pipeline itself is unchanged except for what does the lower-casing, and
-- the `collate "und-x-icu"` pin § 830 added is gone with the `lower()` it
-- pinned: `translate`, `regexp_replace` over named code points and
-- `btrim(x, ' ')` name no collation, so the whole derivation is now collation-
-- free rather than collation-pinned. That also makes the IMMUTABLE marking
-- true in fact: a CHECK over a function whose answer moved with the server's
-- ICU build was a claim the catalogue could not keep, and an ICU upgrade would
-- silently have left validated rows failing their own constraint.
create or replace function public.normalise_exercise_name(p_name text)
returns text
language sql
immutable
parallel safe
returns null on null input
set search_path = ''
as $$
  select btrim(
    regexp_replace(
      translate(public.exercise_fold_case(p_name), U&'\03C2', U&'\03C3'),
      '[\u0009-\u000d\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]+',
      ' ',
      'g'
    ),
    ' '
  );
$$;

comment on function public.normalise_exercise_name(text) is
  'The exercise grouping key: lower-cased through the frozen Unicode 17.0 simple case-fold table in public.exercise_fold_case, final sigma folded to sigma, every run of whitespace collapsed to one space, trimmed. No half depends on the database locale provider, its locale, or the linked ICU version -- the whitespace class is written by code point and the case fold is a frozen table. Must stay identical to normaliseExerciseName in apps/web/src/lib/gym/gym_prs.ts and apps/mobile_android/lib/gym_prs.dart; scripts/check_shared_constants.mjs compares the three.';

revoke execute on function public.normalise_exercise_name(text) from public, anon;
grant  execute on function public.normalise_exercise_name(text) to authenticated;
grant  execute on function public.normalise_exercise_name(text) to service_role;

-- -- Merge the exercise rows the wider fold makes duplicates -----------------
-- `exercises` carries two partial unique indexes over the key --
-- `(author_id, name_key) where author_id is not null` and `(name_key) where
-- author_id is null` -- and the fold only ever WIDENS, so two rows that were
-- distinct can now key the same. Nothing else in the schema can collide:
-- `gym_routine_exercises` and `gym_sets` have no unique index on their key.
--
-- Keeping both is not available: the canonical CHECK forces every row to carry
-- `normalise_exercise_name(name)`, so both would take the new key and the index
-- would refuse one. Aborting is worse -- a migration that can fail on real data
-- is a failed deploy. So the duplicates are merged, deterministically: the
-- oldest row wins (`created_at`, then `id`), every `gym_sets.exercise_id`
-- pointing at a loser is repointed at it, and the losers are deleted. The FK is
-- ON DELETE SET NULL, so repointing BEFORE the delete is what stops a logged
-- set losing its catalogue link. Measured: 0 collisions on the local stack.
--
-- `partition by author_id, ...` covers both indexes at once: window
-- partitioning treats NULLs as equal, so every global row sharing a key lands
-- in one partition exactly as the `where author_id is null` index sees them.
with ranked as (
  select id,
         first_value(id) over (
           partition by author_id, public.normalise_exercise_name(name)
           order by created_at, id
         ) as keep_id
  from public.exercises
), losers as (
  select id, keep_id from ranked where id <> keep_id
)
update public.gym_sets s
set exercise_id = l.keep_id
from losers l
where s.exercise_id = l.id;

with ranked as (
  select id,
         first_value(id) over (
           partition by author_id, public.normalise_exercise_name(name)
           order by created_at, id
         ) as keep_id
  from public.exercises
)
delete from public.exercises e
using ranked r
where e.id = r.id and r.id <> r.keep_id;

-- -- Re-key the three persisted columns --------------------------------------
-- `gym_sets` is keyset-paginated: the batched-predicate idiom restarts at the
-- low end of the primary key on every chunk and is O(n^2/batch), measured at
-- 129.5 s against 6.94 s on 500,000 rows (20270706000002). The two bounded
-- tables -- one row per exercise per routine, one per catalogue entry -- keep
-- the simpler form.
do $$
declare
  batch_size constant integer := 5000;
  lo uuid := '00000000-0000-0000-0000-000000000000';
  seen integer;
begin
  loop
    with chunk as (
      select id from public.gym_sets where id > lo order by id limit batch_size
    ), stamped as (
      update public.gym_sets t
      set exercise_key = public.normalise_exercise_name(t.exercise_name)
      from chunk c
      where t.id = c.id
        and t.exercise_key is distinct from public.normalise_exercise_name(t.exercise_name)
      returning 1
    )
    select (select id from chunk order by id desc limit 1),
           (select count(*) from chunk)
      into lo, seen;
    exit when seen = 0;
  end loop;
end;
$$;

do $$
declare
  batch_size constant integer := 1000;
  touched integer;
begin
  loop
    with candidates as (
      select id
      from public.gym_routine_exercises
      where exercise_key is distinct from public.normalise_exercise_name(exercise_name)
        and coalesce(public.normalise_exercise_name(exercise_name), '') <> ''
      order by id
      limit batch_size
    )
    update public.gym_routine_exercises t
    set exercise_key = public.normalise_exercise_name(t.exercise_name)
    from candidates c
    where t.id = c.id;
    get diagnostics touched = row_count;
    exit when touched = 0;
  end loop;

  loop
    with candidates as (
      select id
      from public.exercises
      where name_key is distinct from public.normalise_exercise_name(name)
        and coalesce(public.normalise_exercise_name(name), '') <> ''
      order by id
      limit batch_size
    )
    update public.exercises t
    set name_key = public.normalise_exercise_name(t.name)
    from candidates c
    where t.id = c.id;
    get diagnostics touched = row_count;
    exit when touched = 0;
  end loop;
end;
$$;

-- -- Re-prove the three canonical CHECKs -------------------------------------
alter table public.gym_sets
  drop constraint gym_sets_exercise_key_canonical;

alter table public.gym_routine_exercises
  drop constraint gym_routine_exercises_exercise_key_canonical;

alter table public.exercises
  drop constraint exercises_name_key_canonical;

alter table public.gym_sets
  add constraint gym_sets_exercise_key_canonical
  check (exercise_key = public.normalise_exercise_name(exercise_name))
  not valid;

alter table public.gym_routine_exercises
  add constraint gym_routine_exercises_exercise_key_canonical
  check (exercise_key = public.normalise_exercise_name(exercise_name))
  not valid;

alter table public.exercises
  add constraint exercises_name_key_canonical
  check (name_key = public.normalise_exercise_name(name))
  not valid;

alter table public.gym_sets
  validate constraint gym_sets_exercise_key_canonical;

alter table public.gym_routine_exercises
  validate constraint gym_routine_exercises_exercise_key_canonical;

alter table public.exercises
  validate constraint exercises_name_key_canonical;
