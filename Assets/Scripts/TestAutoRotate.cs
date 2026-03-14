using UnityEngine;

public class TestAutoRotate : MonoBehaviour
{
    [SerializeField]
    private float rotationSpeed = 10f;

    // Update is called once per frame
    void Update()
    {
        transform.Rotate(Vector3.up, rotationSpeed * Time.deltaTime);
        transform.Rotate(Vector3.right, rotationSpeed * Time.deltaTime);
        transform.Rotate(Vector3.forward, rotationSpeed * Time.deltaTime);
    }
}
