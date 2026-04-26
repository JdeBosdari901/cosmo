import "jsr:@supabase/functions-js/edge-runtime.d.ts";
const SHOPIFY_CLIENT_ID = "377e2e7b97b9297be558b83d93ce2b41";
const SHOPIFY_SHOP = "ashridge-trees";
const SHOPIFY_GQL = `https://${SHOPIFY_SHOP}.myshopify.com/admin/api/2026-01/graphql.json`;
const SHOPIFY_TOKEN_URL = `https://${SHOPIFY_SHOP}.myshopify.com/admin/oauth/access_token`;
const PRODUCTS = [
  {
    title: "Sensation Picot\u00e9e Cosmos Plants",
    sku: "COSMBIPISENPICO-Pk4",
    subtitle: "Cosmea bipinnatus 'Sensation Picot\u00e9e'",
    breadcrumb: "Sensation Picot\u00e9e",
    label: "Picot\u00e9e flowers. Prefers well-drained soil and full sun. Plant 30\u00a0cm apart after last frost."
  },
  {
    title: "Sensation Pinkie Cosmos Plants",
    sku: "COSMBIPISENPINK-Pk4",
    subtitle: "Cosmea bipinnatus 'Sensation Pinkie'",
    breadcrumb: "Sensation Pinkie",
    label: "Pink flowers. Prefers well-drained soil and full sun. Plant 30\u00a0cm apart after last frost."
  },
  {
    title: "Rubenza Cosmos Plants",
    sku: "COSMBIPIRUB-Pk4",
    subtitle: "Cosmea bipinnatus 'Rubenza'",
    breadcrumb: "Rubenza",
    label: "Ruby-red flowers. Prefers well-drained soil and full sun. Plant 30\u00a0cm apart after last frost."
  },
  {
    title: "Fizzy White Cosmos Plants",
    sku: "COSMBIPIFIZWHI-Pk4",
    subtitle: "Cosmea bipinnatus 'Fizzy White'",
    breadcrumb: "Fizzy White",
    label: "White flowers. Prefers well-drained soil and full sun. Plant 30\u00a0cm apart after last frost."
  }
];
const BODY = `<ul class="pdp-specs">
  <li><strong>Type:</strong> Half-hardy annual</li>
  <li><strong>Flowering period:</strong> June\u2013October</li>
  <li><strong>Position:</strong> Full sun</li>
  <li><strong>Soil:</strong> Well-drained, ordinary to poor fertility</li>
  <li><strong>Spacing:</strong> 30 cm (12 in)</li>
  <li><strong>Good for cutting:</strong> Yes</li>
  <li><strong>Sold as:</strong> Jumbo plug seedlings, hand-sown by us</li>
  <li><strong>Plant outdoors:</strong> After last frost (mid-May in most areas)</li>
</ul>`;
async function getShopifyToken() {
  const secret = Deno.env.get("SHOPIFY_CLIENT_KEY");
  if (!secret) throw new Error("SHOPIFY_CLIENT_KEY not set");
  const r = await fetch(SHOPIFY_TOKEN_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Accept: "application/json"
    },
    body: new URLSearchParams({
      grant_type: "client_credentials",
      client_id: SHOPIFY_CLIENT_ID,
      client_secret: secret
    }).toString()
  });
  if (!r.ok) throw new Error(`Shopify token: ${r.status} ${await r.text()}`);
  return (await r.json()).access_token;
}
async function gql(token, query, variables = {}) {
  const r = await fetch(SHOPIFY_GQL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Shopify-Access-Token": token
    },
    body: JSON.stringify({
      query,
      variables
    })
  });
  if (!r.ok) throw new Error(`Shopify GQL HTTP ${r.status}: ${await r.text()}`);
  const json = await r.json();
  if (json.errors?.length) throw new Error(`GQL errors: ${JSON.stringify(json.errors)}`);
  return json;
}
Deno.serve(async (req)=>{
  if (req.method !== "POST") return new Response(JSON.stringify({
    error: "POST required"
  }), {
    status: 405
  });
  const results = [];
  try {
    const token = await getShopifyToken();
    for (const p of PRODUCTS){
      const entry = {
        sku: p.sku,
        title: p.title
      };
      // Check if already exists
      const safeSku = p.sku.replace(/'/g, "\\'");
      const lookup = await gql(token, `{ productVariants(first:1, query:"sku:'${safeSku}'") { nodes { id product { id handle status } } } }`);
      const existing = lookup?.data?.productVariants?.nodes?.[0];
      if (existing) {
        entry.shopify_status = `already_exists: ${existing.product.handle} (${existing.product.status})`;
        results.push(entry);
        continue;
      }
      const setResult = await gql(token, `mutation ProductSet($synchronous: Boolean!, $input: ProductSetInput!) {
          productSet(synchronous: $synchronous, input: $input) {
            product {
              id handle status
              variants(first: 1) { nodes { id sku inventoryPolicy } }
            }
            userErrors { field message }
          }
        }`, {
        synchronous: true,
        input: {
          title: p.title,
          status: "DRAFT",
          vendor: "Ashridge",
          productType: "Bedding",
          tags: [
            "Packs"
          ],
          descriptionHtml: BODY,
          productOptions: [
            {
              name: "Form",
              values: [
                {
                  name: "Seedling"
                }
              ]
            },
            {
              name: "Size",
              values: [
                {
                  name: "4 Jumbo Plugs"
                }
              ]
            }
          ],
          variants: [
            {
              price: "8.99",
              sku: p.sku,
              inventoryPolicy: "CONTINUE",
              optionValues: [
                {
                  optionName: "Form",
                  name: "Seedling"
                },
                {
                  optionName: "Size",
                  name: "4 Jumbo Plugs"
                }
              ]
            }
          ],
          metafields: [
            // product_data namespace — all single_line_text_field except label_description
            {
              namespace: "product_data",
              key: "breadcrumb_name",
              value: p.breadcrumb,
              type: "single_line_text_field"
            },
            {
              namespace: "product_data",
              key: "subtitle",
              value: p.subtitle,
              type: "single_line_text_field"
            },
            {
              namespace: "product_data",
              key: "tag_common_name",
              value: `${p.breadcrumb} Cosmos Seedling Plants`,
              type: "single_line_text_field"
            },
            {
              namespace: "product_data",
              key: "tag_latin_name",
              value: p.subtitle,
              type: "single_line_text_field"
            },
            {
              namespace: "product_data",
              key: "label_description",
              value: p.label,
              type: "multi_line_text_field"
            },
            {
              namespace: "product_data",
              key: "planting_start_month",
              value: "April",
              type: "single_line_text_field"
            },
            {
              namespace: "product_data",
              key: "planting_end_month",
              value: "June",
              type: "single_line_text_field"
            },
            // filter namespace — shade is a list type
            {
              namespace: "filter",
              key: "shade",
              value: JSON.stringify([
                "Full Sun"
              ]),
              type: "list.single_line_text_field"
            }
          ]
        }
      });
      const ue = setResult?.data?.productSet?.userErrors ?? [];
      if (ue.length) throw new Error(`productSet userErrors: ${JSON.stringify(ue)}`);
      const prod = setResult?.data?.productSet?.product;
      if (!prod) throw new Error("productSet returned null product");
      entry.shopify_id = prod.id;
      entry.shopify_handle = prod.handle;
      entry.shopify_status = prod.status;
      const v = prod.variants?.nodes?.[0];
      entry.shopify_variant_id = v?.id;
      entry.shopify_variant_sku = v?.sku;
      entry.shopify_inv_policy = v?.inventoryPolicy;
      console.log(`\u2713 ${p.title} \u2192 ${prod.handle}`);
      results.push(entry);
      await new Promise((r)=>setTimeout(r, 2000));
    }
    return new Response(JSON.stringify({
      status: "ok",
      results
    }), {
      headers: {
        "Content-Type": "application/json"
      }
    });
  } catch (err) {
    return new Response(JSON.stringify({
      error: err instanceof Error ? err.message : String(err),
      results
    }), {
      status: 500
    });
  }
});
