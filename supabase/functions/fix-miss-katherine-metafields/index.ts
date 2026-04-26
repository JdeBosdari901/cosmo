import "jsr:@supabase/functions-js/edge-runtime.d.ts";
Deno.serve((_req)=>{
  return new Response(JSON.stringify({
    status: "retired"
  }), {
    status: 410,
    headers: {
      "Content-Type": "application/json"
    }
  });
});
